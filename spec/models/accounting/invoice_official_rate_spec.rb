require "rails_helper"

# F11: a new invoice in a foreign currency starts from the official rate of its date; one that is typed is left as it is (the posting checks it).
RSpec.describe Accounting::Invoice, "official rate" do
  include_context "with_open_fiscal_year"

  let(:day) { Date.current }

  def official(rate = "1.10") = Accounting::ExchangeRate.create!(currency: "USD", rate_date: day, rate: rate, rate_type: :daily, source: "ecb")
  def build_invoice(**attrs) = build(:invoice, fiscal_year: fiscal_year, invoice_date: day, **attrs)

  it "takes the official rate of the invoice date when the currency is foreign and the rate is still the default" do
    official
    invoice = build_invoice(currency: "USD", exchange_rate: 1)
    invoice.valid?
    expect(invoice.exchange_rate).to eq(BigDecimal("1.10"))
  end

  it "keeps the default rate when there is no official one, leaving the posting to refuse with its message" do
    invoice = build_invoice(currency: "USD", exchange_rate: 1)
    invoice.valid?
    expect(invoice.exchange_rate).to eq(1)
  end

  it "leaves a rate that was typed, with or without a reason" do
    official
    typed = build_invoice(currency: "USD", exchange_rate: "1.15", exchange_rate_reason: "Contract")
    typed.valid?
    expect(typed.exchange_rate).to eq(BigDecimal("1.15"))
    unexplained = build_invoice(currency: "USD", exchange_rate: "1.15")
    unexplained.valid?
    expect(unexplained.exchange_rate).to eq(BigDecimal("1.15"))
  end

  it "leaves a posted invoice alone" do
    official
    invoice = create(:invoice, :posted, fiscal_year: fiscal_year, invoice_date: day)
    invoice.update_columns(currency: "USD", exchange_rate: 1)
    invoice.valid?
    expect(invoice.exchange_rate).to eq(1)
  end

  it "does nothing for an invoice in EUR" do
    official
    invoice = build_invoice(currency: "EUR", exchange_rate: 1)
    invoice.valid?
    expect(invoice.exchange_rate).to eq(1)
  end
end
