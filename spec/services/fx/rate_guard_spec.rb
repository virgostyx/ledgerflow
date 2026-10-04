require "rails_helper"

# F11: an operation takes the rate of its date; any other rate is typed by hand, with a reason, by someone who may (rates.override); a rate that
# strays from the official one by more than the entity's alert is warned about.
RSpec.describe Fx::RateGuard do
  include_context "with entity"

  let(:day) { Date.new(2026, 9, 30) }
  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }

  before { Accounting::ExchangeRate.create!(currency: "USD", rate_date: day, rate: "1.10", rate_type: :daily, source: "ecb") }

  def check(rate: "1.10", reason: nil, user: nil, currency: "USD", date: day)
    described_class.call(currency: currency, date: date, rate: BigDecimal(rate), reason: reason, user: user)
  end

  it "has nothing to say about EUR" do
    expect(check(currency: "EUR", rate: "1")).to have_attributes(rate: 1, warning: nil)
  end

  it "accepts the official rate of the date, with no reason" do
    expect(check).to have_attributes(rate: BigDecimal("1.10"), warning: nil)
  end

  it "refuses any other rate without a reason, saying which rate was expected" do
    expect { check(rate: "1.12") }.to raise_error(Fx::RateRefused, /1\.12.*1\.1/m)
  end

  it "refuses a missing rate, naming the currency and the date (criterion 4)" do
    expect { check(date: day + 1) }.to raise_error(Fx::MissingRate, /USD.*01\/10\/2026/m)
  end

  describe "a rate typed by hand, with a reason" do
    it "is accepted from the system, which has no user" do
      expect(check(rate: "1.12", reason: "Rate of the contract")).to have_attributes(rate: BigDecimal("1.12"))
    end

    it "is accepted from a person who may override rates" do
      expect(check(rate: "1.12", reason: "Rate of the contract", user: accountant)).to have_attributes(rate: BigDecimal("1.12"))
    end

    it "is refused to a person who may not" do
      expect { check(rate: "1.12", reason: "Rate of the contract", user: reader) }.to raise_error(Fx::RateRefused, /not allowed/i)
    end

    it "is accepted even when no official rate exists for the date" do
      expect(check(rate: "1.12", reason: "Bank statement", date: day + 1, user: accountant)).to have_attributes(rate: BigDecimal("1.12"))
    end

    it "warns when it strays from the official rate by more than the alert (5 % by default), and not up to it" do
      expect(check(rate: "1.15", reason: "x").warning).to be_nil # 4.5 %
      warning = check(rate: "1.20", reason: "x").warning       # 9.1 %
      expect(warning).to include("9.1 %", "1.1")
      entity.update!(rate_alert_pct: 10)
      expect(check(rate: "1.20", reason: "x").warning).to be_nil
    end

    it "does not warn when there is no official rate to compare with" do
      expect(check(rate: "5", reason: "x", date: day + 1).warning).to be_nil
    end
  end
end
