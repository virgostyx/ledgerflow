require "rails_helper"

# F13c: personal access tokens made from Settings, for an entity that turned the public API on (no BudgetFlow needed).
RSpec.describe "API tokens in Settings", type: :request do
  include_context "with_open_fiscal_year"

  let(:admin) { create(:user, role: :admin) }

  before do
    create(:user_entity, :admin, user: admin, entity: entity)
    sign_in admin
  end

  it "offers the scopes of the public API (not those of BudgetFlow) and creates a token that works at once" do
    get new_accounting_settings_api_client_path
    expect(response.body).to include("entries:post", "Requests a minute", "Expires on").and not_include("invoices:write")

    post accounting_settings_api_clients_path,
         params: { api_client: { name: "ERP", scopes: [ "", "accounts:read" ], expires_at: 10.days.from_now.to_date.iso8601, rate_limit_per_minute: "120" } }
    expect(response).to have_http_status(:ok)
    key = response.body[/lf_[\w-]+/]
    client = ApiClient.authenticate(key)
    expect(client).to have_attributes(owner: admin, scopes: %w[accounts:read], rate_limit_per_minute: 120)
    expect(client.expires_at.to_date).to eq(10.days.from_now.to_date)

    get "/api/v1/accounts", headers: { "Authorization" => "Bearer #{key}" }
    expect(response).to have_http_status(:ok)

    get accounting_settings_api_clients_path
    expect(response.body).to include("ERP", "Expires").and not_include(key)
  end

  it "re-renders the form for an expiry in the past" do
    post accounting_settings_api_clients_path, params: { api_client: { name: "ERP", scopes: [ "accounts:read" ], expires_at: 1.day.ago.to_date.iso8601 } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("expiry must be in the future")
  end

  it "shows a token whose date has passed as expired" do
    client, = ApiClient.issue!(entity: entity, name: "Old", scopes: %w[accounts:read], owner: admin, expires_at: 1.day.from_now)
    travel(2.days) do
      get accounting_settings_api_clients_path
      expect(response.body).to include("Expired")
      expect(ApiClient.authenticate("lf_x")).to be_nil
    end
    expect(client).to be_persisted
  end
end
