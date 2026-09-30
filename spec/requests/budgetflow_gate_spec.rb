require "rails_helper"

# The BudgetFlow integration is opt-in per entity: an entity that did not declare it must not be influenced by it,
# nor see anything of it (settings, screens, API).
RSpec.describe "BudgetFlow integration gate", type: :request do
  let(:admin)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let(:entity)     { create(:entity) }
  let!(:admin_membership)      { create(:user_entity, :admin, user: admin, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  describe "the declaration" do
    it "is off by default" do
      expect(Entity.new.budgetflow_enabled).to be false
      expect(entity.budgetflow?).to be false
    end

    it "is made with a checkbox when the entity is created" do
      sign_in admin

      post entities_path, params: { entity: { name: "Fondation", legal_name: "Fondation ASBL", country: "BE", budgetflow_enabled: "1" } }
      expect(Entity.find_by(name: "Fondation")).to be_budgetflow_enabled

      post entities_path, params: { entity: { name: "Other", legal_name: "Other ASBL", country: "BE" } }
      expect(Entity.find_by(name: "Other")).not_to be_budgetflow_enabled
    end

    it "can be changed in the settings by the entity administrator" do
      sign_in admin

      get edit_accounting_settings_entity_path
      expect(response.body).to include("This entity uses BudgetFlow")

      patch accounting_settings_entity_path, params: { entity: { name: entity.name, budgetflow_enabled: "1" } }
      expect(entity.reload).to be_budgetflow_enabled

      patch accounting_settings_entity_path, params: { entity: { name: entity.name, budgetflow_enabled: "0" } }
      expect(entity.reload).not_to be_budgetflow_enabled
    end

    it "cannot be changed by an accountant, who does not even see the checkbox" do
      sign_in accountant

      get edit_accounting_settings_entity_path
      expect(response.body).not_to include("BudgetFlow")

      patch accounting_settings_entity_path, params: { entity: { name: entity.name, budgetflow_enabled: "1" } }
      expect(entity.reload).not_to be_budgetflow_enabled
    end
  end

  describe "an entity that does not use BudgetFlow" do
    before { sign_in admin }

    it "has no API Clients link and no access to the screen" do
      get accounting_settings_root_path
      expect(response.body).not_to include("API Clients")

      get accounting_settings_api_clients_path
      expect(response).to have_http_status(:not_found)
      get new_accounting_settings_api_client_path
      expect(response).to have_http_status(:not_found)
      expect { post accounting_settings_api_clients_path, params: { api_client: { name: "X", scopes: [ "invoices:read" ] } } }
        .not_to change(ApiClient, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "cannot have an API client at all" do
      expect { ApiClient.issue!(entity: entity, name: "BudgetFlow", scopes: []) }.to raise_error(ActiveRecord::RecordInvalid, /BudgetFlow/)
    end
  end

  describe "an entity that declared BudgetFlow" do
    before do
      entity.update!(budgetflow_enabled: true)
      sign_in admin
    end

    it "shows the API Clients link and screen" do
      get accounting_settings_root_path
      expect(response.body).to include("API Clients")

      get accounting_settings_api_clients_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "the API" do
    let(:entity)  { create(:entity, budgetflow_enabled: true) }
    let(:issued)  { ApiClient.issue!(entity: entity, name: "BudgetFlow", scopes: %w[invoices:read invoices:write partners:write]) }
    let(:headers) { { "Authorization" => "Bearer #{issued.last}" } }

    it "answers 403 to every call once the entity no longer uses BudgetFlow" do
      get "/api/v1/ping", headers: headers
      expect(response).to have_http_status(:ok)

      entity.update!(budgetflow_enabled: false)

      get "/api/v1/ping", headers: headers
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to match(/BudgetFlow/)
      get "/api/v1/invoice_events", headers: headers
      expect(response).to have_http_status(:forbidden)
      put "/api/v1/partners/P1", headers: headers, params: { name: "X" }, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "answers 403 to the legacy JWT of an entity that does not use BudgetFlow" do
      other = create(:entity)
      jwt = Api::JwtService.encode({ entity_id: other.id })

      get "/api/v1/invoices", headers: { "Authorization" => "Bearer #{jwt}" }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
