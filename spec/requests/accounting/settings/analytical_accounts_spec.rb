require "rails_helper"

RSpec.describe "Accounting::Settings::AnalyticalAccounts", type: :request do
  let(:admin)   { create(:user, role: :admin) }
  let!(:axis)   { create(:analytical_axis, :proj) }
  let!(:account) { create(:analytical_account, analytical_axis: axis,
                           code: "PROJ-001", label_fr: "Project Alpha") }

  before { sign_in admin }

  describe "GET /accounting/settings/analytical_axes/:axis_id/analytical_accounts/new" do
    it "returns 200" do
      get new_accounting_settings_analytical_axis_analytical_account_path(axis)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /accounting/settings/analytical_axes/:axis_id/analytical_accounts" do
    let(:valid_attrs) { { code: "PROJ-002", label_fr: "Project Beta" } }

    it "creates an account and redirects" do
      expect {
        post accounting_settings_analytical_axis_analytical_accounts_path(axis),
             params: { accounting_analytical_account: valid_attrs }
      }.to change(Accounting::AnalyticalAccount, :count).by(1)
      expect(response).to redirect_to(accounting_settings_analytical_axis_path(axis))
    end

    it "returns 422 with blank label" do
      post accounting_settings_analytical_axis_analytical_accounts_path(axis),
           params: { accounting_analytical_account: { code: "PROJ-002", label_fr: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /accounting/settings/analytical_accounts/:id/edit" do
    it "returns 200" do
      get edit_accounting_settings_analytical_account_path(account)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /accounting/settings/analytical_accounts/:id" do
    it "updates label_fr and redirects" do
      patch accounting_settings_analytical_account_path(account),
            params: { accounting_analytical_account: { label_fr: "Project Alpha (updated)" } }
      expect(response).to redirect_to(accounting_settings_analytical_axis_path(axis))
      expect(account.reload.label_fr).to eq("Project Alpha (updated)")
    end

    it "returns 422 with blank label" do
      patch accounting_settings_analytical_account_path(account),
            params: { accounting_analytical_account: { label_fr: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /accounting/settings/analytical_accounts/:id" do
    it "destroys the account if destroyable" do
      expect {
        delete accounting_settings_analytical_account_path(account)
      }.to change(Accounting::AnalyticalAccount, :count).by(-1)
      expect(response).to redirect_to(accounting_settings_analytical_axis_path(axis))
    end

    it "redirects with alert if not destroyable" do
      create(:analytical_annotation, analytical_account: account, analytical_axis: axis)
      delete accounting_settings_analytical_account_path(account)
      expect(response).to redirect_to(accounting_settings_analytical_axis_path(axis))
      expect(flash[:alert]).to be_present
    end
  end
end
