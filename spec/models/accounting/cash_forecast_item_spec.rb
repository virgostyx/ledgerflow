require "rails_helper"

RSpec.describe Accounting::CashForecastItem, type: :model do
  include_context "with entity"

  subject(:item) { build(:cash_forecast_item) }

  it { is_expected.to be_valid }
  it { is_expected.to validate_presence_of(:label) }
  it { is_expected.to validate_numericality_of(:amount).is_greater_than(0) }

  it "rejects an end date before the first date" do
    item.assign_attributes(first_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 4, 1))
    expect(item).not_to be_valid
  end

  describe "#occurrences_between" do
    it "returns the single date for a one-off item inside the window" do
      item.assign_attributes(recurrence: :once, first_date: Date.new(2026, 5, 10))
      expect(item.occurrences_between(Date.new(2026, 5, 1), Date.new(2026, 5, 31))).to eq([ Date.new(2026, 5, 10) ])
      expect(item.occurrences_between(Date.new(2026, 6, 1), Date.new(2026, 6, 30))).to be_empty
    end

    it "repeats monthly, quarterly and yearly, keeping the day (clamped to short months)" do
      item.assign_attributes(recurrence: :monthly, first_date: Date.new(2026, 1, 31))
      expect(item.occurrences_between(Date.new(2026, 2, 1), Date.new(2026, 4, 30))).to eq([ Date.new(2026, 2, 28), Date.new(2026, 3, 31), Date.new(2026, 4, 30) ])
      item.recurrence = :quarterly
      expect(item.occurrences_between(Date.new(2026, 1, 1), Date.new(2026, 12, 31)).size).to eq(4)
      item.recurrence = :yearly
      expect(item.occurrences_between(Date.new(2026, 1, 1), Date.new(2028, 12, 31)).size).to eq(3)
    end

    it "stops at the end date and ignores inactive items" do
      item.assign_attributes(recurrence: :monthly, first_date: Date.new(2026, 1, 10), end_date: Date.new(2026, 3, 10))
      expect(item.occurrences_between(Date.new(2026, 1, 1), Date.new(2026, 12, 31)).size).to eq(3)
      item.active = false
      expect(item.occurrences_between(Date.new(2026, 1, 1), Date.new(2026, 12, 31))).to be_empty
    end
  end
end
