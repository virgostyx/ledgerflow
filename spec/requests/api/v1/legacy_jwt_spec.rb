require "rails_helper"

# F01 review: the historic shared-secret JWT has no owner and no scope. It stays available only while the operator turns
# it on, only on the routes that declare a scope, and every call leaves a trace in the entity's audit trail.
RSpec.describe "The legacy JWT", type: :request do
  include_context "with_authenticated_api"
  include_context "with_open_fiscal_year"

  let(:entity) { create(:entity, budgetflow_enabled: true) }

  around do |example|
    previous = Rails.configuration.x.legacy_jwt_enabled
    example.run
  ensure
    Rails.configuration.x.legacy_jwt_enabled = previous
  end

  def trail = Accounting::AuditLog.where(entity_id: entity.id, action: "api_legacy_jwt")

  context "when the operator has not turned it on" do
    before { Rails.configuration.x.legacy_jwt_enabled = false }

    it "answers 401, whatever the token, and writes nothing" do
      get "/api/v1/ping", headers: auth_headers

      expect(response).to have_http_status(:unauthorized)
      expect(trail).to be_empty
    end

    it "does not touch the API keys" do
      client, key = ApiClient.issue!(entity: entity, name: "BudgetFlow", scopes: %w[invoices:read])

      get "/api/v1/ping", headers: { "Authorization" => "Bearer #{key}" }

      expect(response).to have_http_status(:ok)
      expect(client.reload.last_used_at).to be_present
    end
  end

  context "when it is turned on" do
    before { Rails.configuration.x.legacy_jwt_enabled = true }

    it "serves the routes that declare a scope, and records each call with its path, status and address" do
      get "/api/v1/ping", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(trail.sole.payload).to include("http_method" => "GET", "path" => "/api/v1/ping", "status" => 200, "ip" => "127.0.0.1")
    end

    it "is refused on a route that declares no scope (it never gets what a key could not)" do
      allow(Api::V1::PingController).to receive(:action_scopes).and_return({})

      get "/api/v1/ping", headers: auth_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "records a call that fails too" do
      get "/api/v1/invoices/0", headers: auth_headers

      expect(trail.sole.payload["status"]).to eq(response.status)
    end

    it "records nothing for a token that does not decode" do
      get "/api/v1/ping", headers: { "Authorization" => "Bearer nonsense" }

      expect(response).to have_http_status(:unauthorized)
      expect(trail).to be_empty
    end
  end

  describe "the read routes that used to be open to the JWT alone" do
    before { Rails.configuration.x.legacy_jwt_enabled = true }

    it "now declare the read scope, so a key can reach them within its owner's rights and nothing else can" do
      expect(Api::V1::JournalEntriesController.action_scopes).to eq(index: "invoices:read", show: "invoices:read")
      expect(Api::V1::ProjectsController.action_scopes).to eq(accounting_summary: "invoices:read")
    end

    it "refuses a key without the read scope" do
      _, key = ApiClient.issue!(entity: entity, name: "Narrow", scopes: %w[partners:write])

      get "/api/v1/journal_entries", headers: { "Authorization" => "Bearer #{key}" }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
