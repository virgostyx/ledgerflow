require "rails_helper"

# F11: what a source gives is stored per entity, once: the same rate again changes nothing, a rate that is zero or negative never gets in.
RSpec.describe Rates::Import do
  include_context "with entity"

  def quote(currency: "USD", date: Date.new(2026, 9, 30), rate: "1.1", type: :daily, source: "ecb") = Rates::Quote.new(currency: currency, date: date, rate: BigDecimal(rate), type: type, source: source)

  it "stores the quotes with their kind, their source and the time of the import" do
    result = described_class.call(quotes: [ quote, quote(currency: "ZMW", rate: "22.5", type: :monthly_average, source: "inforeuro", date: Date.new(2026, 9, 1)) ])

    expect(result).to have_attributes(created: 2, updated: 0, unchanged: 0)
    stored = Accounting::ExchangeRate.find_by!(currency: "USD")
    expect(stored).to have_attributes(rate: BigDecimal("1.1"), rate_type: "daily", source: "ecb", rate_date: Date.new(2026, 9, 30))
    expect(stored.imported_at).to be_within(1.minute).of(Time.current)
  end

  it "does nothing the second time, and says so" do
    described_class.call(quotes: [ quote ])
    expect(described_class.call(quotes: [ quote ])).to have_attributes(created: 0, updated: 0, unchanged: 1)
    expect(Accounting::ExchangeRate.count).to eq(1)
  end

  it "updates a rate the source has corrected, without making a second row" do
    described_class.call(quotes: [ quote ])
    expect(described_class.call(quotes: [ quote(rate: "1.2") ])).to have_attributes(updated: 1)
    expect(Accounting::ExchangeRate.sole.rate).to eq(BigDecimal("1.2"))
  end

  it "keeps the rates of another source for the same day apart" do
    described_class.call(quotes: [ quote, quote(source: "csv:bank.csv", rate: "1.12") ])
    expect(Accounting::ExchangeRate.count).to eq(2)
  end

  it "rejects a rate that is zero or negative, naming it, and takes the others" do
    result = described_class.call(quotes: [ quote(rate: "0"), quote(currency: "GBP", rate: "-0.8"), quote(currency: "JPY", rate: "176.99") ])

    expect(result.created).to eq(1)
    expect(result.rejected.map { |q, _| q.currency }).to eq(%w[USD GBP])
    expect(result.rejected.map(&:last).join).to match(/positive/i)
    expect(Accounting::ExchangeRate.pluck(:currency)).to eq([ "JPY" ])
  end

  it "ignores a currency the application does not know, and EUR" do
    result = described_class.call(quotes: [ quote(currency: "XYZ"), quote(currency: "EUR", rate: "1"), quote ])
    expect(result).to have_attributes(created: 1, ignored: 2)
  end

  it "gives a rate typed in a file the reason that says where it came from, and who brought it" do
    user = create(:user)
    described_class.call(quotes: [ quote(type: :manual, source: "csv:bank.csv") ], user: user)
    expect(Accounting::ExchangeRate.sole).to have_attributes(reason: "Imported from csv:bank.csv", created_by: user)
  end

  it "keeps the rates of each entity to itself" do
    other = create(:entity)
    ActsAsTenant.with_tenant(other) { described_class.call(quotes: [ quote ]) }
    described_class.call(quotes: [ quote(rate: "1.5") ])
    expect(Accounting::ExchangeRate.sole.rate).to eq(BigDecimal("1.5"))
  end
end
