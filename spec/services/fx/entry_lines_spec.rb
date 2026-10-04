require "rails_helper"

# F11: the lines of a manual entry in a foreign currency, as the form sends them (currency, amount in currency, rate): the server converts to EUR at the
# rate of the date, signs the amount like the line, and checks the rate like an invoice's.
RSpec.describe Fx::EntryLines do
  include_context "with entity"

  let(:day) { Date.new(2026, 9, 30) }
  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }

  before { Accounting::ExchangeRate.create!(currency: "USD", rate_date: day, rate: "1.25", rate_type: :daily, source: "ecb") }

  def normalize(lines, reason: nil, user: nil) = described_class.call(lines, date: day, reason: reason, user: user)

  it "leaves a line in EUR as it is" do
    lines = { "0" => { "account_id" => "1", "debit" => "10.00", "credit" => "" } }
    expect(normalize(lines).lines).to eq(lines)
  end

  it "drops the side the form sends for a line that is not in a foreign currency" do
    lines = { "0" => { "account_id" => "1", "debit" => "10.00", "credit" => "", "currency" => "EUR", "amount_currency" => "", "side" => "debit" } }
    expect(normalize(lines).lines["0"]).not_to have_key("side")
  end

  it "converts the amount in currency at the official rate, to the side the person filled: EUR on the debit, the amount signed" do
    result = normalize({ "0" => { "account_id" => "1", "debit" => "", "credit" => "", "currency" => "USD", "amount_currency" => "1000", "side" => "debit" } })

    expect(result.error).to be_nil
    expect(result.lines["0"]).to include("debit" => BigDecimal("800.00"), "credit" => 0, "currency" => "USD", "amount_currency" => BigDecimal("1000"), "exchange_rate" => BigDecimal("1.25"))
  end

  it "signs a credit negative, and puts the euros on the credit" do
    result = normalize({ "0" => { "currency" => "USD", "amount_currency" => "500", "side" => "credit" } })
    expect(result.lines["0"]).to include("credit" => BigDecimal("400.00"), "debit" => 0, "amount_currency" => BigDecimal("-500"))
  end

  it "takes the side from the euros already typed when the form did not send one" do
    result = normalize({ "0" => { "currency" => "USD", "amount_currency" => "500", "debit" => "", "credit" => "400" } })
    expect(result.lines["0"]).to include("credit" => BigDecimal("400.00"), "amount_currency" => BigDecimal("-500"))
  end

  it "ignores a rate typed by someone who may not override, and takes the official one" do
    result = normalize({ "0" => { "currency" => "USD", "amount_currency" => "1000", "side" => "debit", "exchange_rate" => "2" } }, reason: "x", user: reader)
    expect(result.lines["0"]["exchange_rate"]).to eq(BigDecimal("1.25"))
  end

  it "takes a rate typed by someone who may, with a reason, and warns of a big gap with the official one" do
    result = normalize({ "0" => { "currency" => "USD", "amount_currency" => "1000", "side" => "debit", "exchange_rate" => "1.5" } }, reason: "Rate of the bank", user: accountant)
    expect(result.lines["0"]).to include("exchange_rate" => BigDecimal("1.5"), "debit" => Fx::Convert.to_eur(BigDecimal("1000"), BigDecimal("1.5")))
    expect(result.warning).to include("away from the official rate")
  end

  it "refuses a typed rate without a reason" do
    result = normalize({ "0" => { "currency" => "USD", "amount_currency" => "1000", "side" => "debit", "exchange_rate" => "1.5" } }, user: accountant)
    expect(result.error).to match(/reason/i)
  end

  it "refuses with the message that names the currency and the date when there is no rate" do
    result = normalize({ "0" => { "currency" => "GBP", "amount_currency" => "10", "side" => "debit" } })
    expect(result.error).to include("GBP", "30/09/2026")
  end

  it "refuses an amount that is not a number or not positive" do
    expect(normalize({ "0" => { "currency" => "USD", "amount_currency" => "abc", "side" => "debit" } }).error).to match(/amount/i)
    expect(normalize({ "0" => { "currency" => "USD", "amount_currency" => "-5", "side" => "debit" } }).error).to match(/positive/i)
  end

  it "does not touch a line that is marked for removal" do
    lines = { "0" => { "id" => "3", "_destroy" => "1", "currency" => "USD", "amount_currency" => "abc" } }
    expect(normalize(lines).error).to be_nil
  end

  it "does not touch a foreign line with no amount: it is a blank line, the form drops it" do
    expect(normalize({ "0" => { "currency" => "USD", "amount_currency" => "" } }).error).to be_nil
  end
end
