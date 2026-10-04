require "rails_helper"

# F11: which rate an operation takes, from the rules of the entity; a rate that is missing is never replaced by a guess (criterion 4).
RSpec.describe Fx::RateFor do
  include_context "with entity"

  let(:day) { Date.new(2026, 9, 30) }

  def put(rate, date: day, type: :daily, currency: "USD", source: "ecb", reason: nil)
    Accounting::ExchangeRate.create!(currency: currency, rate_date: date, rate: rate, rate_type: type, source: source, reason: reason)
  end

  def rate_for(currency = "USD", document: day, accounting: nil) = described_class.call(currency, document_date: document, accounting_date: accounting || document)

  it "is 1 for EUR, with no rate on file" do
    expect(rate_for("EUR")).to eq(1)
  end

  describe "the daily rate (the default)" do
    it "takes the rate of the day" do
      put("1.10")
      put("1.20", date: day - 1)
      expect(rate_for).to eq(BigDecimal("1.10"))
    end

    it "takes a rate typed by hand for that day before the published one" do
      put("1.10")
      put("1.12", type: :manual, source: "manual", reason: "Rate of the bank")
      expect(rate_for).to eq(BigDecimal("1.12"))
    end

    it "does not take a monthly average or a closing rate" do
      put("1.10", type: :monthly_average, source: "inforeuro")
      put("1.10", type: :closing, source: "manual")
      expect { rate_for }.to raise_error(Fx::MissingRate)
    end
  end

  describe "a missing rate (criterion 4)" do
    it "refuses, naming the currency, the date and the screen where to enter it" do
      error = begin; rate_for; rescue Fx::MissingRate => e; e; end
      expect(error.message).to include("USD", "30/09/2026", "Settings > Exchange rates")
      expect(error).to have_attributes(currency: "USD", date: day)
    end

    it "never takes the last rate known, a Saturday included" do
      put("1.10", date: Date.new(2026, 9, 25)) # a Friday
      expect { rate_for("USD", document: Date.new(2026, 9, 26)) }.to raise_error(Fx::MissingRate)
    end

    it "takes the last published rate only for a currency the entity turned that fallback on for, and says so" do
      put("1.10", date: Date.new(2026, 9, 25))
      entity.update!(rate_fallback_currencies: [ "USD" ])
      expect(rate_for("USD", document: Date.new(2026, 9, 26))).to eq(BigDecimal("1.10"))
      put("30", date: Date.new(2026, 9, 25), currency: "ZMW")
      expect { rate_for("ZMW", document: Date.new(2026, 9, 26)) }.to raise_error(Fx::MissingRate)
    end

    it "does not go back further than 7 days with the fallback on (a rate that old is a gap, not a weekend)" do
      put("1.10", date: day - 40)
      entity.update!(rate_fallback_currencies: [ "USD" ])
      expect { rate_for }.to raise_error(Fx::MissingRate)
    end
  end

  describe "the policy of the entity" do
    it "takes the monthly average of the month of the date" do
      entity.update!(rate_policy: :monthly_average)
      put("1.08", date: day.beginning_of_month, type: :monthly_average, source: "inforeuro")
      put("1.50")
      expect(rate_for).to eq(BigDecimal("1.08"))
      expect { rate_for("USD", document: Date.new(2026, 10, 15)) }.to raise_error(Fx::MissingRate)
    end

    it "takes only a rate typed by hand when the policy is manual" do
      entity.update!(rate_policy: :manual)
      put("1.10")
      expect { rate_for }.to raise_error(Fx::MissingRate)
      put("1.15", type: :manual, source: "manual", reason: "Contract rate")
      expect(rate_for).to eq(BigDecimal("1.15"))
    end

    it "reads the date of the document or the accounting date, as the entity chose" do
      put("1.10", date: Date.new(2026, 9, 1))
      put("1.20", date: Date.new(2026, 9, 30))
      expect(rate_for("USD", document: Date.new(2026, 9, 1), accounting: Date.new(2026, 9, 30))).to eq(BigDecimal("1.10"))
      entity.update!(rate_date_basis: :accounting_date)
      expect(rate_for("USD", document: Date.new(2026, 9, 1), accounting: Date.new(2026, 9, 30))).to eq(BigDecimal("1.20"))
    end

    it "does not see the rates of another entity" do
      ActsAsTenant.with_tenant(create(:entity)) { put("1.10") }
      expect { rate_for }.to raise_error(Fx::MissingRate)
    end
  end

  describe ".closing" do
    it "takes the closing rate of the date, exactly" do
      put("1.09", type: :closing, source: "manual")
      expect(described_class.closing("USD", day)).to eq(BigDecimal("1.09"))
    end

    it "refuses without it, naming the currency and the date, and never takes a daily rate in its place" do
      put("1.10")
      error = begin; described_class.closing("USD", day); rescue Fx::MissingRate => e; e; end
      expect(error.message).to include("USD", "30/09/2026", "closing")
    end

    it "is 1 for EUR" do
      expect(described_class.closing("EUR", day)).to eq(1)
    end
  end
end
