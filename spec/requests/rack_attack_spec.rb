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

    it "bloque la 301e requête d'une même IP avec un 429 JSON et Retry-After" do
      # A different bearer each time, so only the IP counter can trip.
      301.times { |i| get "/api/v1/invoices", headers: { "Authorization" => "Bearer lf_k#{i}", "REMOTE_ADDR" => "1.2.3.7" } }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)).to include("error" => "Too Many Requests")
      expect(response.headers["Retry-After"].to_i).to be_between(1, 60)
    end
  end

  describe "throttle API — 300 req / min par clé, quelle que soit l'IP" do
    def call(key, ip) = get("/api/v1/invoices", headers: { "Authorization" => "Bearer #{key}", "REMOTE_ADDR" => ip })

    it "bloque une clé après 300 requêtes réparties sur des IP différentes, sans toucher aux autres clés" do
      300.times { |i| call("lf_busy", "10.0.#{i / 250}.#{(i % 250) + 1}") }
      expect(response).not_to have_http_status(:too_many_requests)

      call("lf_busy", "10.9.9.9")
      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("application/json")
      expect(response.headers["Retry-After"].to_i).to be_between(1, 60)

      call("lf_other", "10.9.9.10")
      expect(response).not_to have_http_status(:too_many_requests)
    end

    it "ne compte pas les requêtes sans jeton dans le compteur par clé" do
      3.times { |i| get "/api/v1/invoices", headers: { "REMOTE_ADDR" => "10.8.8.#{i + 1}" } }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "429 hors API" do
    it "reste en texte brut pour le login" do
      6.times do
        post user_session_path, params: { user: { email: "t@example.com", password: "x" } }, headers: { "REMOTE_ADDR" => "1.2.3.8" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to eq("Too Many Requests\n")
    end
  end
end

RSpec.describe "Rack::Attack passkey endpoints", type: :request do
  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  after { Rack::Attack.enabled = false }

  it "throttles passkey and recovery code sign-in per IP" do
    6.times { post recovery_code_session_path, params: { email: "a@b.c", recovery_code: "x" }, headers: { "REMOTE_ADDR" => "1.2.3.9" } }
    expect(response).to have_http_status(:too_many_requests)
  end
end
