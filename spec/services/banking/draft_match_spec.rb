require "rails_helper"

# F02: a match books a payment entry as a DRAFT (the assistant, or an exact automatic match, never validates). The invoice is
# paid when the entry is validated, which also settles the bank transaction. A match can be undone: a draft is deleted, a
# validated entry reversed.
RSpec.describe "Matching a bank line to an invoice as a draft" do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let!(:bank_gl)     { create(:account, code: "550000", label_fr: "Banque", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:receivable)  { create(:account, code: "400000", label_fr: "Clients", account_type: :asset, normal_balance: :debit) }
  let!(:bank_journal) { create(:journal, :bank, default_account: bank_gl) }
  let(:bank_account)  { create(:bank_account, journal: bank_journal) }
  let(:invoice) { create(:invoice, :customer, :posted, fiscal_year: fiscal_year).tap { |i| i.update_columns(total_incl_vat: BigDecimal("1210")) } }
  let(:tx) { create(:bank_transaction, bank_account: bank_account, amount: BigDecimal("1210")) }

  def book_draft = Accounting::BookInvoiceReceipt.call(transaction: tx, invoice: invoice, fiscal_year: fiscal_year, draft: true)

  describe "booking as a draft" do
    it "creates a draft payment entry, marks the transaction as matched, and leaves the invoice unpaid" do
      expect(book_draft).to be_success

      entry = tx.reload.journal_entry
      expect(entry).to be_draft
      expect(tx).to be_matched
      expect(invoice.reload).to be_posted
      expect(entry.lines.find_by(account: receivable)).to have_attributes(credit: BigDecimal("1210"), invoice_id: invoice.id, partner_id: invoice.partner_id)
    end

    it "already counts the draft against the invoice, so the same invoice is not offered twice" do
      book_draft

      expect(invoice.reload.remaining_amount).to eq(0)
    end

    it "keeps booking as before (validated) when no draft is asked for" do
      Accounting::BookInvoiceReceipt.call(transaction: tx, invoice: invoice, fiscal_year: fiscal_year)

      expect(tx.reload).to be_reconciled
      expect(tx.journal_entry).to be_posted
      expect(invoice.reload).to be_paid
    end

    it "refuses to book a transaction that is already matched" do
      book_draft

      expect(Accounting::BookInvoiceReceipt.call(transaction: tx, invoice: invoice, fiscal_year: fiscal_year, draft: true)).to be_failure
    end
  end

  describe "validating the draft" do
    before { book_draft }

    it "settles the bank transaction and pays the invoice" do
      expect(Accounting::PostJournalEntry.call(entry: tx.reload.journal_entry)).to be_success

      expect(tx.reload).to be_reconciled
      expect(invoice.reload).to be_paid
    end

    it "leaves an invoice that is only partly covered open" do
      tx.update_columns(amount: BigDecimal("500"))
      tx.journal_entry.lines.each { |l| l.update_columns(debit: l.debit.positive? ? 500 : 0, credit: l.credit.positive? ? 500 : 0) }

      Accounting::PostJournalEntry.call(entry: tx.journal_entry)

      expect(tx.reload).to be_reconciled
      expect(invoice.reload).to be_posted
    end

    it "does nothing to a transaction when another entry is validated" do
      other = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year)

      Accounting::PostJournalEntry.call(entry: other)

      expect(tx.reload).to be_matched
    end
  end

  describe Banking::UndoMatch do
    it "deletes the draft of a matched transaction, which becomes pending again and frees the invoice" do
      book_draft
      entry = tx.reload.journal_entry

      result = described_class.call(transaction: tx, user: user)

      expect(result).to be_success
      expect(Accounting::JournalEntry.exists?(entry.id)).to be false
      expect(tx.reload).to be_pending
      expect(tx.journal_entry).to be_nil
      expect(invoice.reload.remaining_amount).to eq(BigDecimal("1210"))
    end

    it "reverses the validated entry of a reconciled transaction, with a reason, and reopens the invoice" do
      Accounting::BookInvoiceReceipt.call(transaction: tx, invoice: invoice, fiscal_year: fiscal_year)
      entry = tx.reload.journal_entry

      result = described_class.call(transaction: tx, user: user, reason: "Wrong customer")

      expect(result).to be_success
      expect(entry.reload).to be_reversed
      expect(tx.reload).to be_pending
      expect(tx.journal_entry).to be_nil
      expect(invoice.reload).to be_posted
      expect(invoice.remaining_amount).to eq(BigDecimal("1210"))
    end

    it "needs a reason to reverse a validated entry" do
      Accounting::BookInvoiceReceipt.call(transaction: tx, invoice: invoice, fiscal_year: fiscal_year)

      result = described_class.call(transaction: tx, user: user)

      expect(result).to be_failure
      expect(tx.reload).to be_reconciled
    end

    it "does nothing to a pending transaction" do
      expect(described_class.call(transaction: tx, user: user)).to be_failure
    end

    it "audits the undoing, with the reason" do
      book_draft

      described_class.call(transaction: tx, user: user)
      Accounting::BookInvoiceReceipt.call(transaction: tx.reload, invoice: invoice, fiscal_year: fiscal_year)
      described_class.call(transaction: tx.reload, user: user, reason: "Wrong customer")

      rows = Accounting::AuditLog.where(action: "bank_match_undone").order(:id)
      expect(rows.size).to eq(2)
      expect(rows.last.reason).to eq("Wrong customer")
    end

    it "is refused for a period that is locked, a locked draft being deletable but a validated entry not" do
      Accounting::BookInvoiceReceipt.call(transaction: tx, invoice: invoice, fiscal_year: fiscal_year)
      create(:period_lock, starts_on: tx.transaction_date.beginning_of_month, ends_on: tx.transaction_date.end_of_month)

      expect(described_class.call(transaction: tx, user: user, reason: "x")).to be_failure
      expect(tx.reload).to be_reconciled
    end
  end

  describe "an invoice whose payment was reversed" do
    it "no longer counts the reversed entry as a payment" do
      Accounting::BookInvoiceReceipt.call(transaction: tx, invoice: invoice, fiscal_year: fiscal_year)
      Accounting::ReverseJournalEntry.call(entry: tx.reload.journal_entry, reason: "oops")

      expect(invoice.reload.paid_amount).to eq(0)
    end
  end
end
