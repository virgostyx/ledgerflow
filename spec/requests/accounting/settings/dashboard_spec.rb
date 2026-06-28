require "rails_helper"

RSpec.describe "Accounting::Settings::Dashboard", type: :request do
  include_context 'with entity'

  let(:admin)     { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)   { create(:user, role: :manager) }
  let(:auditor)   { create(:user, role: :auditor) }

  let!(:admin_membership)      { create(:user_entity, :admin,      user: admin,      entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager,    user: manager,    entity: entity) }
  let!(:auditor_membership)    { create(:user_entity, :auditor,    user: auditor,    entity: entity) }

  describe "GET /accounting/settings" do
    context "as admin" do
      before { sign_in admin }

      it "returns 200" do
        get accounting_settings_root_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "as accountant" do
      before { sign_in accountant }

      it "returns 200" do
        get accounting_settings_root_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "as manager" do
      before { sign_in manager }

      it "redirects with not authorized" do
        get accounting_settings_root_path
        expect(response).to redirect_to(accounting_root_path)
      end
    end

    context "as auditor" do
      before { sign_in auditor }

      it "redirects with not authorized" do
        get accounting_settings_root_path
        expect(response).to redirect_to(accounting_root_path)
      end
    end

    context "unauthenticated" do
      it "redirects to sign in" do
        get accounting_settings_root_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
