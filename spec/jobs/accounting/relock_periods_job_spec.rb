require "rails_helper"

# F01: a temporary unlock closes again by itself.
RSpec.describe Accounting::RelockPeriodsJob do
  include_context "with entity"

  let(:user) { create(:user) }

  def reopened(relock_at) = create(:period_lock, status: :unlocked, unlocked_by: user, unlocked_at: 5.hours.ago, unlock_reason: "Late invoice", relock_at: relock_at)

  it "locks again the periods whose deadline has passed, and records it" do
    due = reopened(1.minute.ago)

    expect(described_class.perform_now).to eq(1)

    expect(due.reload).to be_locked
    expect(due.relock_at).to be_nil
    row = Accounting::AuditLog.where(action: "relock_period", auditable_id: due.id).sole
    expect(row.payload).to include("starts_on" => due.starts_on.to_s, "ends_on" => due.ends_on.to_s)
  end

  it "leaves open a period whose deadline has not come, and one that was unlocked without a deadline" do
    waiting = reopened(2.hours.from_now)
    open_ended = reopened(nil)

    expect(described_class.perform_now).to eq(0)

    expect(waiting.reload).to be_unlocked
    expect(open_ended.reload).to be_unlocked
  end

  it "does nothing the second time" do
    reopened(1.minute.ago)
    described_class.perform_now

    expect(described_class.perform_now).to eq(0)
    expect(Accounting::AuditLog.where(action: "relock_period").count).to eq(1)
  end

  it "works across entities, each under its own audit chain" do
    mine = reopened(1.minute.ago)
    other = create(:entity)
    theirs = ActsAsTenant.with_tenant(other) { create(:period_lock, status: :unlocked, unlocked_by: user, unlocked_at: 5.hours.ago, unlock_reason: "x", relock_at: 1.minute.ago) }

    expect(described_class.perform_now).to eq(2)

    expect(mine.reload).to be_locked
    expect(ActsAsTenant.with_tenant(other) { theirs.reload }).to be_locked
    expect(ActsAsTenant.with_tenant(other) { Accounting::AuditLog.where(action: "relock_period").count }).to eq(1)
  end
end
