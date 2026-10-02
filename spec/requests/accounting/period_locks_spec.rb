require "rails_helper"

RSpec.describe "Accounting::PeriodLocks", type: :request do
  include_context "with entity"

  let(:owner)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)    { create(:user, role: :manager) }
  let!(:owner_membership)      { create(:user_entity, :admin,      user: owner,      entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager,    user: manager,    entity: entity) }

  let(:params) { { period_lock: { kind: "accounting", starts_on: "2026-03-01", ends_on: "2026-03-31", lock_reason: "March reviewed" } } }

  before { sign_in accountant }

  describe "GET /accounting/period_locks" do
    it "lists the locks with their reasons" do
      create(:period_lock, starts_on: Date.new(2026, 2, 1), ends_on: Date.new(2026, 2, 28), lock_reason: "February done")

      get accounting_period_locks_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("February done")
    end

    it "offers the unlock form to the owner only" do
      create(:period_lock)
      get accounting_period_locks_path
      expect(response.body).not_to include("Reason (required)")

      sign_out accountant
      sign_in owner
      get accounting_period_locks_path
      expect(response.body).to include("Reason (required)")
    end
  end

  describe "POST /accounting/period_locks" do
    it "locks the period for an accountant" do
      expect { post accounting_period_locks_path, params: params }.to change(Accounting::PeriodLock.locked, :count).by(1)

      expect(response).to redirect_to(accounting_period_locks_path)
      expect(Accounting::PeriodLock.last.locked_by).to eq(accountant)
    end

    it "shows the error when the dates are inverted" do
      post accounting_period_locks_path, params: { period_lock: { starts_on: "2026-03-31", ends_on: "2026-03-01" } }

      expect(Accounting::PeriodLock.count).to eq(0)
      expect(flash[:alert]).to be_present
    end

    it "refuses a manager" do
      sign_out accountant
      sign_in manager

      expect { post accounting_period_locks_path, params: params }.not_to change(Accounting::PeriodLock, :count)
    end
  end

  describe "POST /accounting/period_locks/:id/unlock" do
    let!(:lock) { create(:period_lock) }

    it "refuses an accountant: only the owner unlocks" do
      post unlock_accounting_period_lock_path(lock), params: { reason: "needed" }

      expect(lock.reload).to be_locked
    end

    it "unlocks for the owner, with a reason" do
      sign_out accountant
      sign_in owner

      post unlock_accounting_period_lock_path(lock), params: { reason: "Late supplier invoice" }

      expect(lock.reload).to be_unlocked
      expect(lock.unlocked_by).to eq(owner)
      expect(response).to redirect_to(accounting_period_locks_path)
    end

    it "keeps the period locked and says why when the reason is missing" do
      sign_out accountant
      sign_in owner

      post unlock_accounting_period_lock_path(lock), params: { reason: "" }

      expect(lock.reload).to be_locked
      expect(flash[:alert]).to match(/reason/i)
    end
  end

  it "does not show another entity's locks nor let one be unlocked" do
    other = create(:entity)
    foreign = ActsAsTenant.with_tenant(other) { create(:period_lock, lock_reason: "FOREIGN") }
    sign_out accountant
    sign_in owner

    get accounting_period_locks_path
    expect(response.body).not_to include("FOREIGN")

    post unlock_accounting_period_lock_path(foreign), params: { reason: "x" }
    expect(foreign.reload).to be_locked
  end
end
