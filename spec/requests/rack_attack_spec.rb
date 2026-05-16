require "rails_helper"

RSpec.describe "Rack::Attack", type: :request do
  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  after { Rack::Attack.enabled = false }

  describe "throttle login — 5 tentatives / 20s par IP" do
    it "autorise les 5 premières tentatives" do
      5.times do
        post user_session_path,
             params: { user: { email: "test@example.com", password: "wrong" } },
             headers: { "REMOTE_ADDR" => "1.2.3.4" }
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end

    it "bloque la 6e tentative avec 429" do
      6.times do
        post user_session_path,
             params: { user: { email: "test@example.com", password: "wrong" } },
             headers: { "REMOTE_ADDR" => "1.2.3.5" }
      end
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "throttle API — 300 req / min par IP" do
    let(:user) { create(:user, role: :admin) }

    it "autorise les premières requêtes" do
      sign_in user
      get "/api/v1/projects/1/accounting_summary",
          headers: { "REMOTE_ADDR" => "1.2.3.6" }
      expect(response).not_to have_http_status(:too_many_requests)
    end
  end
end
