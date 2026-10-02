require "rails_helper"

RSpec.describe "Locking and unlocking a period" do
  include_context "with entity"

  let(:user) { create(:user) }
  let(:range) { { starts_on: Date.new(2026, 3, 1), ends_on: Date.new(2026, 3, 31) } }

  describe Accounting::LockPeriod do
    it "locks the period and records who, when and why" do
      result = described_class.call(**range, kind: :accounting, reason: "March reviewed", user: user)

      expect(result).to be_success
      lock = result[:lock]
      expect(lock).to be_locked
      expect(lock.locked_by).to eq(user)
      expect(lock.locked_at).to be_present
      expect(lock.lock_reason).to eq("March reviewed")
    end

    it "writes one audit entry" do
      expect { described_class.call(**range, user: user) }.to change(Accounting::AuditLog.where(action: "lock_period"), :count).by(1)
    end
  end

  describe Accounting::UnlockPeriod do
    let!(:lock) { create(:period_lock, **range) }

    it "refuses to unlock without a reason" do
      result = described_class.call(lock: lock, reason: " ", user: user)

      expect(result).to be_failure
      expect(lock.reload).to be_locked
    end

    it "unlocks with a reason and records who, when and why" do
      result = described_class.call(lock: lock, reason: "Late supplier invoice", user: user)

      expect(result).to be_success
      expect(lock.reload).to be_unlocked
      expect(lock.unlocked_by).to eq(user)
      expect(lock.unlocked_at).to be_present
      expect(lock.unlock_reason).to eq("Late supplier invoice")
    end

    it "keeps the reason in the audit trail" do
      described_class.call(lock: lock, reason: "Late supplier invoice", user: user)

      expect(Accounting::AuditLog.find_by(action: "unlock_period").reason).to eq("Late supplier invoice")
    end

    it "refuses to unlock a period that is already unlocked" do
      lock.update!(status: :unlocked)

      expect(described_class.call(lock: lock, reason: "again", user: user)).to be_failure
    end
  end
end
