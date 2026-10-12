require "rails_helper"

# B01b §5 "Éligibilité d'une facture": an invoice is offered for payment only when everything holds; otherwise it is shown greyed, with the exact reason.
RSpec.describe Payments::Eligibility do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:today)    { Date.current }
  let(:execution) { today + 2 }
  let(:supplier) { create(:partner, :supplier, name: "Acme Ltd", iban: nil) }
  let(:owner)    { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let!(:account) { create(:partner_bank_account, :verified, partner: supplier, iban: "BE68539007547034", created_by: owner) }

  def posted(partner: supplier, due: today + 5, unit_price: 1000, currency: "EUR", **attrs)
    invoice = create(:invoice, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal, partner: partner, due_date: due, currency: currency, **attrs.except(:payment_status, :iban))
    create(:invoice_line, invoice: invoice, account: account_604, unit_price: unit_price, quantity: 1, vat_rate: "21.00")
    invoice.update_columns(exchange_rate: 1.1, exchange_rate_reason: "rate") if currency != "EUR"
    result = Accounting::PostInvoice.call(invoice: invoice)
    raise result.message if result.failure?

    invoice.reload.tap { |i| i.update_columns(attrs.slice(:payment_status, :iban).transform_values { |v| v.is_a?(Symbol) ? Accounting::Invoice.payment_statuses.fetch(v) : v }) if attrs.slice(:payment_status, :iban).any? }
  end

  def rows(**options) = described_class.call(execution_date: execution, **options).index_by { |row| row.invoice.id }

  def reasons(row) = row.reasons.map(&:code)

  it "offers an approved or approval-free invoice of a supplier with a verified account, in euros, whose rest is open" do
    invoice = posted
    row = rows.fetch(invoice.id)

    expect(row).to be_eligible
    expect(row.reasons).to be_empty
    expect(row.rest).to eq(BigDecimal("1210.00"))
    expect(row.account).to eq(account)
  end

  describe "the exact reason an invoice is not offered" do
    it "an invoice waiting for approval, on hold, or disputed" do
      pending_invoice = posted(payment_status: :to_approve)
      held = posted(payment_status: :on_hold)
      disputed = posted(payment_status: :disputed)
      result = rows

      expect(reasons(result.fetch(pending_invoice.id))).to eq([ :awaiting_approval ])
      expect(reasons(result.fetch(held.id))).to eq([ :on_hold ])
      expect(reasons(result.fetch(disputed.id))).to eq([ :disputed ])
      expect(result.fetch(pending_invoice.id).reasons.first.message).to match(/waiting for its approval/i)
    end

    it "approved and scheduled ones are offered: scheduled is a payment already planned, shown by its batch" do
      approved = posted(payment_status: :approved)

      expect(rows.fetch(approved.id)).to be_eligible
    end

    it "an invoice or a supplier on hold by a person, with the reason they wrote" do
      by_invoice = posted
      Payments::Hold.create!(invoice: by_invoice, reason: "Goods not received", created_by: owner)
      other_supplier = create(:partner, :supplier, name: "Beta SA", iban: nil)
      create(:partner_bank_account, :verified, partner: other_supplier, iban: "FR1420041010050500013M02606", created_by: owner)
      by_supplier = posted(partner: other_supplier)
      Payments::Hold.create!(partner: other_supplier, reason: "Dispute in progress", created_by: owner)
      result = rows

      expect(reasons(result.fetch(by_invoice.id))).to eq([ :hold ])
      expect(result.fetch(by_invoice.id).reasons.first.message).to include("Goods not received")
      expect(result.fetch(by_supplier.id).reasons.first.message).to include("Dispute in progress")
    end

    it "an invoice whose hold was lifted is offered again" do
      invoice = posted
      Payments::Hold.create!(invoice: invoice, reason: "x", created_by: owner, released_at: Time.current)

      expect(rows.fetch(invoice.id)).to be_eligible
    end

    it "an invoice already in an active batch (of the new flow or of the earlier one), named" do
      new_flow = posted
      batch = Payments::Batch.create!(bank_account: create(:bank_account), reference: "LOT-9", requested_execution_date: execution)
      item = batch.items.create!(partner: supplier, iban: account.iban, holder_name: "Acme Ltd", amount: "100.00", end_to_end_id: "E1", remittance: "x")
      item.item_invoices.create!(invoice: new_flow, amount: "100.00")
      legacy = posted
      legacy_batch = Accounting::PaymentBatch.create!(bank_account: create(:bank_account), requested_execution_date: execution)
      legacy_batch.lines.create!(invoice: legacy, amount: 100)
      result = rows

      expect(reasons(result.fetch(new_flow.id))).to eq([ :in_batch ])
      expect(result.fetch(new_flow.id).reasons.first.message).to include("LOT-9")
      expect(reasons(result.fetch(legacy.id))).to eq([ :in_batch ])
    end

    it "an invoice of a cancelled batch is offered again" do
      invoice = posted
      batch = Payments::Batch.create!(bank_account: create(:bank_account), reference: "LOT-9", requested_execution_date: execution)
      item = batch.items.create!(partner: supplier, iban: account.iban, holder_name: "Acme Ltd", amount: "100.00", end_to_end_id: "E1", remittance: "x")
      item.item_invoices.create!(invoice: invoice, amount: "100.00")
      batch.update!(status: :cancelled)

      expect(rows.fetch(invoice.id)).to be_eligible
    end

    it "a supplier with no bank account, an unverified one, one still observed, and one that is blocked" do
      none = create(:partner, :supplier, name: "None SA", iban: nil)
      waiting = create(:partner, :supplier, name: "Waiting SA", iban: nil).tap { |p| create(:partner_bank_account, partner: p, iban: "FR1420041010050500013M02606", created_by: owner) }
      observed = create(:partner, :supplier, name: "Observed SA", iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: "NL91ABNA0417164300", created_by: owner, cooling_until: 3.hours.from_now) }
      blocked = create(:partner, :supplier, name: "Blocked SA", iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: "DE89370400440532013000", created_by: owner, status: :blocked) }
      invoices = { none: posted(partner: none), waiting: posted(partner: waiting), observed: posted(partner: observed), blocked: posted(partner: blocked) }
      result = rows

      expect(invoices.transform_values { |i| reasons(result.fetch(i.id)) }).to eq(none: [ :no_account ], waiting: [ :account_unverified ], observed: [ :account_observed ], blocked: [ :account_blocked ])
      expect(result.fetch(invoices[:observed].id).reasons.first.message).to match(/observed until/i)
      expect(result.fetch(invoices[:none].id).reasons.first.message).to match(/Bank details/)
    end

    it "an invoice that carries another IBAN than the verified account, until that one is verified too" do
      other = posted(iban: "FR1420041010050500013M02606")
      same = posted(iban: "BE68539007547034")
      nothing = posted
      result = rows

      expect(reasons(result.fetch(other.id))).to eq([ :iban_differs ])
      expect(result.fetch(same.id)).to be_eligible
      expect(result.fetch(nothing.id)).to be_eligible
    end

    it "an invoice in another currency than the euro" do
      usd = posted(currency: "USD")

      expect(reasons(rows.fetch(usd.id))).to eq([ :currency ])
    end

    it "a credit note, which is netted against the invoices of the supplier when a batch is made, never paid" do
      note = posted(document_type: :credit_note)

      expect(reasons(rows.fetch(note.id))).to eq([ :credit_note ])
    end

    it "an invoice with nothing left to pay" do
      invoice = posted
      line = invoice.journal_entry.lines.find_by(account: account_440)
      payment = Accounting::JournalEntry.new(journal: create(:journal, :bank), fiscal_year: fiscal_year, entry_date: today, status: :draft, reference: nil)
      payment.save!
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      debit = create(:journal_entry_line, journal_entry: payment, account: account_440, partner: supplier, debit: 1210, credit: 0)
      create(:journal_entry_line, journal_entry: payment, account: account_550, debit: 0, credit: 1210)
      Accounting::PostJournalEntry.call!(entry: payment)
      Accounting::LineAllocation.create!(debit_line: debit, credit_line: line, amount: 1210, allocated_on: today)

      expect(reasons(rows.fetch(invoice.id))).to eq([ :nothing_open ])
    end
  end

  describe "what is left to pay" do
    it "is the rest of a part-paid invoice, nothing more" do
      invoice = posted
      line = invoice.journal_entry.lines.find_by(account: account_440)
      payment = Accounting::JournalEntry.new(journal: create(:journal, :bank), fiscal_year: fiscal_year, entry_date: today, status: :draft, reference: nil)
      payment.save!
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      debit = create(:journal_entry_line, journal_entry: payment, account: account_440, partner: supplier, debit: 400, credit: 0)
      create(:journal_entry_line, journal_entry: payment, account: account_550, debit: 0, credit: 400)
      Accounting::PostJournalEntry.call!(entry: payment)
      Accounting::LineAllocation.create!(debit_line: debit, credit_line: line, amount: 400, allocated_on: today)

      row = rows.fetch(invoice.id)

      expect(row).to be_eligible
      expect(row.rest).to eq(BigDecimal("810.00"))
    end
  end

  describe "the due date" do
    it "preselects what falls due up to the execution date plus a week, overdue ones included" do
      late = posted(due: today - 10)
      soon = posted(due: execution + 7)
      later = posted(due: execution + 8)
      result = rows

      expect(result.fetch(late.id)).to be_preselected
      expect(result.fetch(late.id)).to be_late
      expect(result.fetch(soon.id)).to be_preselected
      expect(result.fetch(later.id)).not_to be_preselected
    end

    it "still offers what is not yet due, for a person to pick, and flags it as early" do
      later = posted(due: execution + 20)
      row = rows.fetch(later.id)

      expect(row).to be_eligible
      expect(row).to be_early
    end

    it "takes the window of the person" do
      later = posted(due: execution + 20)

      expect(rows(window_days: 30).fetch(later.id)).to be_preselected
    end
  end

  it "says several reasons at once, so that nothing is hidden behind the first" do
    invoice = posted(payment_status: :to_approve, iban: "FR1420041010050500013M02606", currency: "USD")

    expect(reasons(rows.fetch(invoice.id))).to contain_exactly(:awaiting_approval, :iban_differs, :currency)
  end

  it "does not list what is not payable at all: a draft, a cancelled invoice, a sales invoice, a paid one, one of another entity" do
    draft = create(:invoice, :supplier, :draft, :with_lines, fiscal_year: fiscal_year, partner: supplier)
    sale = create(:invoice, :customer, :posted, fiscal_year: fiscal_year)
    cancelled = posted.tap { |i| i.update_columns(status: Accounting::Invoice.statuses[:cancelled]) }
    paid = posted.tap { |i| i.update_columns(status: Accounting::Invoice.statuses[:paid]) }

    expect(rows.keys).not_to include(draft.id, sale.id, cancelled.id, paid.id)
  end
end
