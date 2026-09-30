require "rails_helper"

RSpec.describe "Accounting::Settings::ApiClients", type: :request do
  include_context "with_open_fiscal_year"
  let(:entity) { create(:entity, budgetflow_enabled: true) } # the API only exists for entities that declared BudgetFlow

  let(:admin)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }

  let!(:admin_membership)      { create(:user_entity, :admin, user: admin, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, user: accountant, entity: entity) }

  let!(:client) { ApiClient.issue!(entity: entity, name: "BudgetFlow", scopes: %w[invoices:read]).first }

  before { sign_in admin }

  describe "GET /accounting/settings/api_clients" do
    it "lists the clients of the entity without any key" do
      other = ApiClient.issue!(entity: create(:entity, budgetflow_enabled: true), name: "Foreign app", scopes: []).first

      get accounting_settings_api_clients_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("BudgetFlow").and not_include(other.name).and not_include(client.key_digest)
    end
  end

  describe "POST /accounting/settings/api_clients" do
    it "creates the client and shows its key once" do
      expect {
        post accounting_settings_api_clients_path,
             params: { api_client: { name: "Payroll", scopes: %w[invoices:write partners:write] } }
      }.to change(ApiClient, :count).by(1)

      expect(response).to have_http_status(:ok)
      key = response.body[/lf_[\w-]+/]
      expect(ApiClient.authenticate(key)).to have_attributes(name: "Payroll", entity: entity,
                                                             scopes: %w[invoices:write partners:write])
      get accounting_settings_api_clients_path
      expect(response.body).not_to include(key)
    end

    it "re-renders the form on invalid input" do
      post accounting_settings_api_clients_path, params: { api_client: { name: "", scopes: [ "everything" ] } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "ignores blank scope checkboxes" do
      post accounting_settings_api_clients_path, params: { api_client: { name: "X", scopes: [ "", "invoices:read" ] } }

      expect(ApiClient.find_by(name: "X").scopes).to eq(%w[invoices:read])
    end
  end

  describe "POST rotate" do
    it "issues a new key and invalidates the old one" do
      old_digest = client.key_digest

      post rotate_accounting_settings_api_client_path(client)

      key = response.body[/lf_[\w-]+/]
      expect(ApiClient.authenticate(key)).to eq(client)
      expect(client.reload.key_digest).not_to eq(old_digest)
    end
  end

  describe "PATCH revoke" do
    it "deactivates the client" do
      patch revoke_accounting_settings_api_client_path(client)

      expect(client.reload).not_to be_active
      expect(response).to redirect_to(accounting_settings_api_clients_path)
    end
  end

  it "cannot touch a client of another entity" do
    foreign = ApiClient.issue!(entity: create(:entity, budgetflow_enabled: true), name: "Foreign", scopes: []).first

    patch revoke_accounting_settings_api_client_path(foreign)

    expect(response).to have_http_status(:not_found)
    expect(foreign.reload).to be_active
  end

  it "is reserved to administrators" do
    sign_in accountant

    get accounting_settings_api_clients_path

    expect(response).to redirect_to(accounting_root_path)
  end
end
