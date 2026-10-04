require "rails_helper"

# F11: posting an invoice in a foreign currency takes the official rate of its date, or a rate typed by hand with a reason; a missing rate refuses.
RSpec.describe "Posting an invoice in a foreign currency" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:sale_journal) { create(:journal, :sale) }
  let(:customer) { create(:partner, :customer) }
  let(:day) { Date.current }

  def usd_invoice(rate: "1.10", reason: nil, price: "1000.00", vat_rate: "0.00")
    inv = create(:invoice, invoice_type: :customer, partner: customer, fiscal_year: fiscal_year, journal: sale_journal, invoice_date: day,
                 currency: "USD", exchange_rate: rate, exchange_rate_reason: reason)
    create(:invoice_line, invoice: inv, account: account_700, quantity: 1, unit_price: price, vat_rate: vat_rate, position: 1)
    inv.compute_totals
    inv.save!
    inv
  end

  def official(rate = "1.10", date: day) = Accounting::ExchangeRate.create!(currency: "USD", rate_date: date, rate: rate, rate_type: :daily, source: "ecb")

  it "values 1 000 USD at 1.10 at 909.09 EUR, balanced in EUR and in USD, with the rate frozen on the lines (criterion 1)" do
    official
    invoice = usd_invoice
    result = Accounting::PostInvoice.call(invoice: invoice)

    expect(result).to be_success, result.message
    lines = invoice.reload.journal_entry.lines
    expect(lines.sum(:debit)).to eq(BigDecimal("909.09"))
    expect(lines.sum(:credit)).to eq(BigDecimal("909.09"))
    expect(lines.sum(:amount_currency)).to eq(0)
    expect(lines.map(&:exchange_rate).uniq).to eq([ BigDecimal("1.10") ])
  end

  it "is refused without a rate for the date, naming the currency and the date, and nothing is booked (criterion 4)" do
    invoice = usd_invoice
    result = Accounting::PostInvoice.call(invoice: invoice)

    expect(result).to be_failure
    expect(result.message).to include("USD", Accounting::DatePresenter.new(day).format, "Settings > Exchange rates")
    expect(invoice.reload).to be_draft
    expect(Accounting::JournalEntry.count).to eq(0)
  end

  it "is refused with a rate that is not the official one and no reason" do
    official
    result = Accounting::PostInvoice.call(invoice: usd_invoice(rate: "1.12"))
    expect(result).to be_failure
    expect(result.message).to include("1.12", "1.1")
  end

  it "takes a rate typed by hand with a reason, even when no official rate exists, and keeps the reason" do
    invoice = usd_invoice(rate: "1.12", reason: "Rate of the contract")
    expect(Accounting::PostInvoice.call(invoice: invoice)).to be_success
    expect(invoice.reload.exchange_rate_reason).to eq("Rate of the contract")
  end

  it "refuses a person who may not override rates, and accepts one who may" do
    reader = create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) }
    accountant = create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) }

    Current.user = reader
    expect(Accounting::PostInvoice.call(invoice: usd_invoice(rate: "1.12", reason: "Contract"))).to be_failure
    Current.user = accountant
    expect(Accounting::PostInvoice.call(invoice: usd_invoice(rate: "1.12", reason: "Contract"))).to be_success
  ensure
    Current.reset
  end

  it "gives a warning when the rate typed strays from the official one by more than the alert" do
    official
    result = Accounting::PostInvoice.call(invoice: usd_invoice(rate: "1.30", reason: "Bank rate"))
    expect(result).to be_success
    expect(result[:rate_warning]).to include("away from the official rate")
  end

  it "leaves an invoice in EUR alone" do
    invoice = create(:invoice, invoice_type: :customer, partner: customer, fiscal_year: fiscal_year, journal: sale_journal, invoice_date: day)
    create(:invoice_line, invoice: invoice, account: account_700, quantity: 1, unit_price: "100.00", vat_rate: "0.00", position: 1)
    invoice.compute_totals
    invoice.save!
    expect(Accounting::PostInvoice.call(invoice: invoice)).to be_success
  end

  it "books the cent that converting line by line leaves on a line of its own, on the exchange difference account" do
    official("7")
    # 10.04 + 21 % VAT (2.11) = 12.15 USD: at 7, 1.74 EUR on the receivable against 1.43 + 0.30 on the revenue and the VAT
    invoice = usd_invoice(rate: "7", price: "10.04", vat_rate: "21.00")
    expect(Accounting::PostInvoice.call(invoice: invoice)).to be_success

    lines = invoice.reload.journal_entry.lines
    expect(lines.sum(:debit)).to eq(lines.sum(:credit))
    expect(lines.joins(:account).find_by(accounting_accounts: { code: "751100" })).to have_attributes(credit: BigDecimal("0.01"), label: "Conversion rounding")
  end
end
