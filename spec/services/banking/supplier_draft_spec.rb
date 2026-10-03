require "rails_helper"

# F02: a payment to a supplier can be left as a DRAFT too (whoever cannot validate): the payment entry exists, the line is matched,
# and validating the entry letters it with the invoice, which is then paid. Whole invoices only, in euros: a deposit or a foreign
# payment settles by allocation, which needs a validated entry.
RSpec.describe "Paying a supplier invoice as a draft" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user) { create(:user) }
  let!(:purchase)  { create(:journal, :purchase, default_account: account_440) }
  let!(:bank_journal) { create(:journal, :bank, default_account: account_550) }
  let(:bank_account) { create(:bank_account, journal: bank_journal) }
  let!(:supplier) { create(:partner, :supplier, :with_iban, external_ref: "S1", name: "BUREAU PLUS SA") }
  let(:invoice) do
    Accounting::ExternalInvoice.upsert(external_ref: "INV-1", partner_external_ref: "S1", invoice_type: "supplier", invoice_date: Date.current.to_s,
                                       lines: [ { account_code: "604000", description: "Work", quantity: "1", unit_price: "100", vat_rate: "0" } ]).invoice
  end
  let(:tx) { create(:bank_transaction, bank_account: bank_account, amount: -100, counterparty_iban: supplier.iban, description: "PAYMENT") }

  def pay_draft(transaction = tx) = Accounting::PayInvoiceFromTransaction.call(transaction: transaction, invoice: invoice, fiscal_year: fiscal_year, draft: true)

  before do
    invoice.update!(supplier_reference: "F-2026-0042") unless invoice.supplier_reference
    Accounting::PostInvoice.call(invoice: invoice) if invoice.draft?
    invoice.reload
  end

  it "books a draft payment, matches the line and leaves the invoice open" do
    expect(pay_draft).to be_success

    entry = tx.reload.journal_entry
    expect(tx).to be_matched
    expect(entry).to be_draft
    expect(entry.lines.find_by(account: account_440)).to have_attributes(debit: BigDecimal("100"), invoice_id: invoice.id)
    expect(invoice.reload).to be_posted
  end

  it "stops proposing the invoice to another line while its draft payment waits" do
    pay_draft
    other = create(:bank_transaction, bank_account: bank_account, amount: -100, counterparty_iban: supplier.iban, description: "AGAIN")

    expect(Accounting::MatchBankTransaction.call(transaction: other)).to be_nil
    expect(Accounting::PayInvoiceFromTransaction.call(transaction: other, invoice: invoice, fiscal_year: fiscal_year, draft: true)).to be_failure
  end

  it "letters the payment with the invoice once the entry is validated, which pays it and settles the line" do
    pay_draft

    expect(Accounting::PostJournalEntry.call(entry: tx.reload.journal_entry)).to be_success

    expect(tx.reload).to be_reconciled
    expect(invoice.reload).to be_paid
    expect(Accounting::JournalEntryLine.where(invoice_id: invoice.id, account: account_440).map(&:lettering_id).compact.uniq.size).to eq(1)
  end

  it "refuses a draft for a deposit: that settles by allocation, which needs a validated entry" do
    result = Accounting::PayInvoiceFromTransaction.call(transaction: tx, invoice: invoice, fiscal_year: fiscal_year, draft: true, invoice_amount: BigDecimal("40"))

    expect(result).to be_failure
    expect(tx.reload).to be_pending
  end

  it "is what confirming the suggestion gives an assistant" do
    tx.update!(description: "FACTURE F-2026-0042")

    result = Accounting::AcceptBankSuggestion.call(transaction: tx, draft: true)

    expect(result).to be_success
    expect(tx.reload).to be_matched
  end

  it "is undone like the others: the draft goes, or the validated payment is unlettered and reversed, and the invoice reopens" do
    pay_draft
    Banking::UndoMatch.call(transaction: tx.reload, user: user)
    expect(tx.reload).to be_pending
    expect(Accounting::MatchBankTransaction.call(transaction: tx)).to be_present

    pay_draft(tx)
    Accounting::PostJournalEntry.call(entry: tx.reload.journal_entry)
    expect(invoice.reload).to be_paid

    expect(Banking::UndoMatch.call(transaction: tx.reload, user: user, reason: "Wrong supplier")).to be_success
    expect(tx.reload).to be_pending
    expect(invoice.reload).to be_posted
  end
end
