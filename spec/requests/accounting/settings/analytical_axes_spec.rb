require "rails_helper"

RSpec.describe "Accounting::Settings::AnalyticalAxes", type: :request do
  include_context 'with entity'

  let(:admin)   { create(:user, role: :admin) }
  let(:manager) { create(:user, role: :manager) }
  let!(:axis)   { create(:analytical_axis, :proj) }

  let!(:admin_membership)   { create(:user_entity, :admin,   user: admin,   entity: entity) }
  let!(:manager_membership) { create(:user_entity, :manager, user: manager, entity: entity) }

  before { sign_in admin }

  describe "GET /accounting/settings/analytical_axes" do
    it "returns 200" do
      get accounting_settings_analytical_axes_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /accounting/settings/analytical_axes/:id/edit" do
    it "returns 200" do
      get edit_accounting_settings_analytical_axis_path(axis)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /accounting/settings/analytical_axes/:id" do
    it "updates label_fr and redirects" do
      patch accounting_settings_analytical_axis_path(axis),
            params: { accounting_analytical_axis: { label_fr: "Updated Projects" } }
      expect(response).to redirect_to(accounting_settings_analytical_axes_path)
      expect(axis.reload.label_fr).to eq("Updated Projects")
    end

    it "updates active status" do
      patch accounting_settings_analytical_axis_path(axis),
            params: { accounting_analytical_axis: { active: false } }
      expect(axis.reload.active).to be false
    end

    it "updates required_for_account_classes" do
      patch accounting_settings_analytical_axis_path(axis),
            params: { accounting_analytical_axis: { required_for_account_classes: [ 6, 7 ] } }
      expect(axis.reload.required_for_account_classes).to contain_exactly(6, 7)
    end

    it "returns 422 with blank label" do
      patch accounting_settings_analytical_axis_path(axis),
            params: { accounting_analytical_axis: { label_fr: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "access control" do
    before { sign_in manager }

    it "redirects manager away from settings" do
      get accounting_settings_analytical_axes_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end
