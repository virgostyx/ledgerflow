require "rails_helper"

RSpec.describe "Accounting::Settings::CustomRoles", type: :request do
  include_context "with entity"

  let(:owner)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let!(:owner_membership)      { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before { sign_in owner }

  it "lists the custom roles and offers the permissions to compose one" do
    CustomRole.create!(name: "Reviewer", permissions: %w[records.view])

    get accounting_settings_custom_roles_path

    expect(response.body).to include("Reviewer", "entries.post", "periods.unlock")
    expect(response.body).not_to include("users.manage") # reserved to the owners
  end

  it "creates a role from ticked permissions" do
    expect { post accounting_settings_custom_roles_path, params: { custom_role: { name: "Reviewer", permissions: [ "", "records.view", "reports.view" ] } } }
      .to change(CustomRole, :count).by(1)

    expect(CustomRole.last.permissions).to eq(%w[records.view reports.view])
    expect(response).to redirect_to(accounting_settings_custom_roles_path)
  end

  it "refuses an invalid role and says why" do
    expect { post accounting_settings_custom_roles_path, params: { custom_role: { name: "", permissions: [ "records.view" ] } } }.not_to change(CustomRole, :count)

    expect(flash[:alert]).to be_present
  end

  it "changes the permissions of a role" do
    role = CustomRole.create!(name: "Reviewer", permissions: %w[records.view])

    patch accounting_settings_custom_role_path(role), params: { custom_role: { permissions: [ "records.view", "entries.post" ] } }

    expect(role.reload.permissions).to eq(%w[records.view entries.post])
  end

  it "deletes an unused role, and refuses to delete one that is held" do
    free = CustomRole.create!(name: "Free", permissions: %w[records.view])
    held = CustomRole.create!(name: "Held", permissions: %w[records.view])
    create(:user_entity, :manager, entity: entity, custom_role: held)

    expect { delete accounting_settings_custom_role_path(free) }.to change(CustomRole, :count).by(-1)
    expect { delete accounting_settings_custom_role_path(held) }.not_to change(CustomRole, :count)
    expect(flash[:alert]).to be_present
  end

  it "is for the owners only" do
    sign_out owner
    sign_in accountant

    expect { post accounting_settings_custom_roles_path, params: { custom_role: { name: "Sneaky", permissions: [ "records.view" ] } } }.not_to change(CustomRole, :count)
  end

  it "is closed while the feature is off" do
    entity.update!(features: entity.features.merge("f01" => false))

    get accounting_settings_custom_roles_path

    expect(response).to redirect_to(accounting_root_path)
  end

  describe "giving a role to an access" do
    let(:role) { CustomRole.create!(name: "Reviewer", permissions: %w[records.view reports.view]) }

    it "offers the custom roles in the access screen" do
      role

      get accounting_settings_memberships_path

      expect(response.body).to include("Reviewer", "custom:#{role.id}")
    end

    it "sets a custom role on an access, and the system role is replaced by it" do
      patch accounting_settings_membership_path(accountant_membership), params: { membership: { role: "custom:#{role.id}" } }

      expect(accountant_membership.reload.custom_role).to eq(role)
      expect(accountant_membership).to be_manager # least privilege behind the custom role
    end

    it "goes back to a system role" do
      accountant_membership.update!(custom_role: role, role: :manager)

      patch accounting_settings_membership_path(accountant_membership), params: { membership: { role: "accountant" } }

      expect(accountant_membership.reload.custom_role).to be_nil
      expect(accountant_membership).to be_accountant
    end

    it "ignores a custom role id that does not exist here" do
      patch accounting_settings_membership_path(accountant_membership), params: { membership: { role: "custom:0" } }

      expect(accountant_membership.reload.custom_role).to be_nil
      expect(flash[:alert]).to be_present
    end
  end
end
