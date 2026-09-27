require "rails_helper"

RSpec.describe Reports::Period, type: :model do
  include_context "with_open_fiscal_year"

  describe ".for_fiscal_year" do
    it "spans the whole fiscal year, labeled by its year" do
      period = described_class.for_fiscal_year(fiscal_year)

      expect(period.start_date).to eq(fiscal_year.start_date)
      expect(period.end_date).to eq(fiscal_year.end_date)
      expect(period.label).to eq(fiscal_year.year.to_s)
    end
  end

  describe ".month" do
    it "returns the nth month by rank in the fiscal year, not by calendar month" do
      shifted = create(:fiscal_year, entity: entity, status: :closed, year: 2099,
                        start_date: Date.new(2026, 4, 1), end_date: Date.new(2027, 3, 31))

      first_month = described_class.month(shifted, 1)
      third_month = described_class.month(shifted, 3)

      expect(first_month.start_date).to eq(Date.new(2026, 4, 1))
      expect(first_month.end_date).to eq(Date.new(2026, 4, 30))
      expect(third_month.start_date).to eq(Date.new(2026, 6, 1))
      expect(third_month.end_date).to eq(Date.new(2026, 6, 30))
    end

    it "clips the last month to the fiscal year's actual end date" do
      last_month = described_class.month(fiscal_year, 12)
      expect(last_month.end_date).to eq(fiscal_year.end_date)
    end
  end

  describe ".as_of" do
    it "spans from the fiscal year's start to the given date" do
      period = described_class.as_of(fiscal_year, fiscal_year.start_date + 10)
      expect(period.start_date).to eq(fiscal_year.start_date)
      expect(period.end_date).to eq(fiscal_year.start_date + 10)
    end
  end

  describe "#comparative_period" do
    it "shifts back by exactly one year for :previous_year" do
      period = described_class.new(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 3, 31),
                                    comparative: :previous_year)
      expect(period.comparative_period).to have_attributes(start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 3, 31))
    end

    it "shifts back by the period's own length for :previous" do
      period = described_class.new(start_date: Date.new(2026, 2, 1), end_date: Date.new(2026, 2, 28),
                                    comparative: :previous)
      expect(period.comparative_period).to have_attributes(start_date: Date.new(2026, 1, 4), end_date: Date.new(2026, 1, 31))
    end

    it "is nil without a comparative mode" do
      period = described_class.new(start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 3, 31))
      expect(period.comparative_period).to be_nil
    end
  end
end
