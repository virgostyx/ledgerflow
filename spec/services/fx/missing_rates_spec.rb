require "rails_helper"

# F11: the screen says which rates are missing for the currencies in use, over the last 30 days a person may still enter documents for.
RSpec.describe Fx::MissingRates do
  include_context "with entity"

  let(:today) { Date.new(2026, 10, 7) } # a Wednesday

  def daily(date, currency: "USD") = Accounting::ExchangeRate.create!(currency: currency, rate_date: date, rate: "1.1", rate_type: :daily, source: "ecb")

  describe "the currencies in use" do
    it "are those of the invoices, the partners, the accounts and the lines, never EUR" do
      create(:partner, currency: "ZMW")
      create(:account, code: "467000", account_class: 4, account_type: :asset, normal_balance: :debit, currency: "JPY")
      create(:invoice, currency: "GBP", exchange_rate: 1.2, exchange_rate_reason: "x")
      expect(Fx::CurrenciesInUse.call).to match_array(%w[ZMW JPY GBP])
    end

    it "are none for an entity that works in EUR" do
      create(:partner)
      expect(Fx::CurrenciesInUse.call).to eq([])
    end
  end

  it "lists the working days of the last 30 without a rate, for each currency in use, not the weekends and not today" do
    create(:partner, currency: "USD")
    (today - 30...today).select(&:on_weekday?).each { |d| daily(d) unless d == today - 2 } # Monday 5 October has none
    missing = described_class.call(today: today)

    expect(missing.map(&:currency)).to eq([ "USD" ])
    expect(missing.first.dates).to eq([ today - 2 ])
  end

  it "lists every working day of the window when there is no rate at all" do
    create(:partner, currency: "USD")
    dates = described_class.call(today: today).first.dates
    expect(dates.size).to eq((today - 30...today).count(&:on_weekday?))
    expect(dates).to all(satisfy(&:on_weekday?))
  end

  it "is empty when the rates are all there" do
    create(:partner, currency: "USD")
    (today - 30...today).each { |d| daily(d) }
    expect(described_class.call(today: today)).to eq([])
  end

  it "looks at the months of the window when the entity works with the monthly average" do
    entity.update!(rate_policy: :monthly_average)
    create(:partner, currency: "USD")
    Accounting::ExchangeRate.create!(currency: "USD", rate_date: Date.new(2026, 10, 1), rate: "1.1", rate_type: :monthly_average, source: "inforeuro")
    missing = described_class.call(today: today)
    expect(missing.first.dates).to eq([ Date.new(2026, 9, 1) ])
  end

  it "says nothing when the entity types its rates by hand: there is no source to wait for" do
    entity.update!(rate_policy: :manual)
    create(:partner, currency: "USD")
    expect(described_class.call(today: today)).to eq([])
  end
end
