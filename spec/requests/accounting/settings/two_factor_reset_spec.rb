require "rails_helper"

# F01: losing the authenticator app: an owner resets the second factor of another person, with a reason, audited.
RSpec.describe "Resetting someone's second factor", type: :request do
  include_context "with entity"

  let(:owner)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let!(:owner_membership)      { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before do
    secret = accountant.begin_totp_enrollment!
    accountant.confirm_totp!(Totp.code(secret))
    accountant.generate_totp_backup_codes!
    sign_in owner
  end

  def reset(membership = accountant_membership, reason: "Lost phone, identity checked by phone")
    post reset_two_factor_accounting_settings_membership_path(membership), params: { reason: reason }
  end

  it "switches the second factor off, removes its backup codes and audits who did it and why" do
    reset

    expect(accountant.reload).not_to be_totp_enabled
    expect(accountant.recovery_codes.totp.count).to eq(0)
    row = Accounting::AuditLog.where(action: "two_factor_reset", auditable_id: accountant.id).sole
    expect(row.user_id).to eq(owner.id)
    expect(row.reason).to eq("Lost phone, identity checked by phone")
    expect(response).to redirect_to(accounting_settings_memberships_path)
  end

  it "makes a role that requires it enrol again at the next request" do
    reset
    sign_out owner
    sign_in accountant

    get accounting_journal_entries_path

    expect(response).to redirect_to(two_factor_path) if Rails.configuration.x.second_factor_required
  end

  it "needs a reason" do
    reset(reason: " ")

    expect(accountant.reload).to be_totp_enabled
    expect(flash[:alert]).to be_present
  end

  it "does not reset one's own second factor (the owner switches it off with a code, if the role allows)" do
    reset(owner_membership)

    expect(flash[:alert]).to be_present
  end

  it "is refused to anyone but an owner" do
    sign_out owner
    sign_in accountant

    reset

    expect(accountant.reload).to be_totp_enabled
  end

  it "only reaches the accesses of this entity" do
    stranger_access = create(:user_entity, :accountant, entity: create(:entity))
    stranger_access.user.tap { |u| u.confirm_totp!(Totp.code(u.begin_totp_enrollment!)) }

    reset(stranger_access)

    expect(response).to have_http_status(:not_found)
    expect(stranger_access.user.reload).to be_totp_enabled
  end

  it "shows the button only for people who have a second factor" do
    plain = create(:user_entity, :manager, entity: entity)

    get accounting_settings_memberships_path

    expect(response.body).to include(reset_two_factor_accounting_settings_membership_path(accountant_membership))
    expect(response.body).not_to include(reset_two_factor_accounting_settings_membership_path(plain))
  end
end
