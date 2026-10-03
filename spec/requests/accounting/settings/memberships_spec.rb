require "rails_helper"

RSpec.describe "Accounting::Settings::Memberships", type: :request do
  include_context "with entity"

  let(:owner)      { create(:user, role: :admin, full_name: "Olivia Owner") }
  let(:accountant) { create(:user, role: :accountant) }
  let!(:owner_membership)      { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before { sign_in owner }

  describe "GET /accounting/settings/memberships" do
    it "lists the people with access and their role" do
      get accounting_settings_memberships_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Olivia Owner", accountant.email)
    end

    it "does not list the people of another entity" do
      stranger = create(:user_entity, :accountant, entity: create(:entity)).user

      get accounting_settings_memberships_path

      expect(response.body).not_to include(stranger.email)
    end

    it "is closed to an accountant" do
      sign_out owner
      sign_in accountant

      get accounting_settings_memberships_path

      expect(response).to redirect_to(accounting_root_path)
    end
  end

  describe "POST /accounting/settings/memberships (invite)" do
    it "gives access to a new person" do
      expect {
        post accounting_settings_memberships_path, params: { membership: { email: "fresh@example.com", full_name: "Fresh Face", role: "manager" } }
      }.to change(UserEntity, :count).by(1)

      expect(response).to redirect_to(accounting_settings_memberships_path)
      expect(UserEntity.last).to be_manager
    end

    it "shows why an invitation is refused" do
      post accounting_settings_memberships_path, params: { membership: { email: accountant.email, full_name: "x", role: "manager" } }

      expect(flash[:alert]).to be_present
    end

    it "is refused to an accountant" do
      sign_out owner
      sign_in accountant

      expect {
        post accounting_settings_memberships_path, params: { membership: { email: "fresh@example.com", full_name: "F", role: "admin" } }
      }.not_to change(UserEntity, :count)
    end
  end

  describe "PATCH /accounting/settings/memberships/:id" do
    it "refuses to make someone an external auditor without an end date, and says so" do
      patch accounting_settings_membership_path(accountant_membership), params: { membership: { role: "auditor" } }

      expect(accountant_membership.reload).to be_accountant
      expect(flash[:alert]).to match(/until|end/i)
    end

    it "limits an access to some journals, and lifts the limit when none is ticked" do
      journal = create(:journal, :sale)

      patch accounting_settings_membership_path(accountant_membership), params: { membership: { journal_ids: [ "", journal.id.to_s ] } }
      expect(accountant_membership.reload.journal_ids).to eq([ journal.id ])

      patch accounting_settings_membership_path(accountant_membership), params: { membership: { journal_ids: [ "" ] } }
      expect(accountant_membership.reload.journal_ids).to be_nil
    end

    it "shows the journals on the screen" do
      create(:journal, :sale, label_fr: "Ventes SPECIAL")

      get accounting_settings_memberships_path

      expect(response.body).to include("Ventes SPECIAL")
    end

    it "changes a role, deactivates and sets an expiry date" do
      patch accounting_settings_membership_path(accountant_membership), params: { membership: { role: "auditor", valid_until: (Date.current + 10).to_s } }

      expect(accountant_membership.reload).to be_auditor
      expect(accountant_membership.valid_until).to eq(Date.current + 10)

      patch accounting_settings_membership_path(accountant_membership), params: { membership: { active: "0" } }
      expect(accountant_membership.reload).not_to be_active
    end

    it "takes effect on the person's very next request" do
      patch accounting_settings_membership_path(accountant_membership), params: { membership: { active: "0" } }
      sign_out owner
      sign_in accountant

      get accounting_journal_entries_path

      expect(response).to redirect_to("/onboarding/entity/new")
    end

    it "refuses to demote the last owner and says why" do
      patch accounting_settings_membership_path(owner_membership), params: { membership: { role: "accountant" } }

      expect(owner_membership.reload).to be_admin
      expect(flash[:alert]).to match(/last owner/i)
    end

    it "cannot touch the access of another entity" do
      foreign = create(:user_entity, :accountant, entity: create(:entity))

      patch accounting_settings_membership_path(foreign), params: { membership: { role: "admin" } }

      expect(foreign.reload).to be_accountant
    end

    it "is refused to an accountant" do
      sign_out owner
      sign_in accountant

      patch accounting_settings_membership_path(accountant_membership), params: { membership: { role: "admin" } }

      expect(accountant_membership.reload).to be_accountant
    end
  end
end
