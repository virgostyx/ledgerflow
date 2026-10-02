require "rails_helper"

RSpec.describe Accounting::PeriodLock, type: :model do
  include_context "with entity"

  let!(:lock) { create(:period_lock, starts_on: Date.new(2026, 3, 1), ends_on: Date.new(2026, 3, 31)) }

  describe ".covering" do
    it "covers the first and the last day of a locked period" do
      expect(described_class.covering(Date.new(2026, 3, 1))).to contain_exactly(lock)
      expect(described_class.covering(Date.new(2026, 3, 31))).to contain_exactly(lock)
    end

    it "does not cover the day before nor the day after" do
      expect(described_class.covering(Date.new(2026, 2, 28))).to be_empty
      expect(described_class.covering(Date.new(2026, 4, 1))).to be_empty
    end

    it "ignores an unlocked period" do
      lock.update!(status: :unlocked)

      expect(described_class.covering(Date.new(2026, 3, 15))).to be_empty
    end

    it "ignores the locks of another entity" do
      other = create(:entity)
      ActsAsTenant.with_tenant(other) { create(:period_lock, starts_on: Date.new(2026, 5, 1), ends_on: Date.new(2026, 5, 31)) }

      expect(described_class.covering(Date.new(2026, 5, 15))).to be_empty
    end
  end

  it "refuses a period that ends before it starts" do
    expect(build(:period_lock, starts_on: Date.new(2026, 3, 2), ends_on: Date.new(2026, 3, 1))).not_to be_valid
  end
end
