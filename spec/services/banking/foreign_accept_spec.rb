require "rails_helper"

# A payment from a foreign account that names the supplier's invoice number is proposed, and accepting it books the payment with the euro value of the
# rate of the movement's date. With no rate for that date nothing is booked and the person is told the EUR amount is needed.
RSpec.describe "Accepting a suggestion on a foreign account" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:purchase)     { create(:journal, :purchase, default_account: account_440) }
  let!(:misc)         { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let!(:bank_journal) { create(:journal, :bank, default_account: account_550) }
  let(:zmw_account)   { create(:bank_account, journal: bank_journal).tap { |b| b.update_columns(currency: "ZMW") } }
  let!(:supplier)     { create(:partner, :supplier, :with_iban, external_ref: "S1") }
  let(:day) { Date.new(2026, 10, 20) }
  let(:invoice) do
    # 2750 ZMW booked at 25 = 110 EUR
    Accounting::ExternalInvoice.upsert(external_ref: "Z1", partner_external_ref: "S1", invoice_type: "supplier", invoice_date: day.to_s, currency: "ZMW", exchange_rate: "25",
                                       supplier_reference: "VOL-ZMW1-0007", lines: [ { account_code: "604000", description: "Work", quantity: "1", unit_price: "2750", vat_rate: "0" } ]).invoice
  end
  let(:tx) { create(:bank_transaction, bank_account: zmw_account, amount: -2750, currency: "ZMW", transaction_date: day, description: "Transfer #7 VOL-ZMW1-0007 Supplier") }

  before { Accounting::PostInvoice.call(invoice: invoice) if invoice.draft? }

  it "books it with the EUR value of the rate of the date of the movement, and the exchange difference" do
    Accounting::ExchangeRate.create!(currency: "ZMW", rate_date: day, rate: "27.5", rate_type: :daily, source: "inforeuro")

    result = Accounting::AcceptBankSuggestion.call(transaction: tx)

    expect(result).to be_success, result.message
    expect(tx.reload).to be_reconciled
    expect(invoice.reload).to be_paid
    expect(tx.journal_entry.lines.sum(:credit)).to eq(BigDecimal("100")) # 2750 / 27.5
  end

  it "books nothing when no rate is known for that date, and says the EUR amount is needed" do
    result = Accounting::AcceptBankSuggestion.call(transaction: tx)

    expect(result).to be_failure
    expect(result.message).to match(/EUR amount/)
    expect(tx.reload).to be_pending
    expect(invoice.reload).to be_posted
  end
end
