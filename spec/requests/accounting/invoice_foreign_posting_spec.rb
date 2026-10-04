require "rails_helper"

# F11, posting an invoice in a foreign currency from the screen: the refusal names the currency and the date; a rate far from the official one warns.
RSpec.describe "Posting a foreign-currency invoice", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:sale_journal) { create(:journal, :sale) }
  let(:customer) { create(:partner, :customer) }

  before { sign_in accountant }

  def usd_invoice(rate:, reason: nil)
    inv = create(:invoice, invoice_type: :customer, partner: customer, fiscal_year: fiscal_year, journal: sale_journal, invoice_date: Date.current,
                 currency: "USD", exchange_rate: rate, exchange_rate_reason: reason)
    create(:invoice_line, invoice: inv, account: account_700, quantity: 1, unit_price: "1000.00", vat_rate: "0.00", position: 1)
    inv.compute_totals
    inv.save!
    inv
  end

  it "refuses without a rate, with the message that names the currency, the date and the screen" do
    invoice = usd_invoice(rate: "1.1")
    post validate_invoice_accounting_invoice_path(invoice)

    expect(flash[:alert]).to include("USD", Accounting::DatePresenter.new(Date.current).format, "Settings > Exchange rates")
    expect(invoice.reload).to be_draft
  end

  it "posts at the official rate of the day" do
    Accounting::ExchangeRate.create!(currency: "USD", rate_date: Date.current, rate: "1.25", rate_type: :daily, source: "ecb")
    invoice = usd_invoice(rate: "1.25")
    post validate_invoice_accounting_invoice_path(invoice)

    expect(invoice.reload).to be_posted
    expect(invoice.journal_entry.lines.sum(:debit)).to eq(BigDecimal("800"))
  end

  it "posts at a typed rate with its reason, and warns when it is far from the official one" do
    Accounting::ExchangeRate.create!(currency: "USD", rate_date: Date.current, rate: "1.25", rate_type: :daily, source: "ecb")
    invoice = usd_invoice(rate: "1.50", reason: "Rate of the contract")
    post validate_invoice_accounting_invoice_path(invoice)

    expect(invoice.reload).to be_posted
    expect(flash[:alert]).to include("away from the official rate")
  end

  it "shows the reason field and the rate unit on the form of an invoice that has a typed rate" do
    invoice = usd_invoice(rate: "1.50", reason: "Rate of the contract")
    get edit_accounting_invoice_path(invoice)
    expect(response.body).to include("Units of currency for 1 EUR", "Rate of the contract")
  end
end
