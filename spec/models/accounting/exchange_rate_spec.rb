require "rails_helper"

# F11: a rate is the number of units of foreign currency for 1 EUR, with a kind and a source; never zero or negative.
RSpec.describe Accounting::ExchangeRate, type: :model do
  include_context "with entity"

  def rate(**attrs) = described_class.new({ currency: "USD", rate_date: Date.new(2026, 9, 30), rate: "1.1", rate_type: :daily, source: "ecb" }.merge(attrs))

  it "keeps 8 decimals" do
    expect(rate(rate: "1.12345678").tap(&:save!).reload.rate).to eq(BigDecimal("1.12345678"))
  end

  it "refuses a rate that is zero or negative" do
    expect(rate(rate: "0")).not_to be_valid
    expect(rate(rate: "-1.1")).not_to be_valid
  end

  it "refuses EUR, and a code that is not three letters" do
    expect(rate(currency: "EUR")).not_to be_valid
    expect(rate(currency: "US")).not_to be_valid
  end

  it "has four kinds: daily, monthly_average, closing and manual" do
    expect(described_class.rate_types.keys).to eq(%w[daily monthly_average closing manual])
  end

  it "is unique per currency, date, kind and source" do
    rate.save!
    expect(rate).not_to be_valid
    expect(rate(source: "manual-file")).to be_valid
    expect(rate(rate_type: :closing)).to be_valid
    expect(rate(rate_date: Date.new(2026, 9, 29))).to be_valid
  end

  it "needs a reason when it is typed by hand" do
    expect(rate(rate_type: :manual, source: "manual", reason: nil)).not_to be_valid
    expect(rate(rate_type: :manual, source: "manual", reason: "Rate of the bank statement")).to be_valid
  end
end
