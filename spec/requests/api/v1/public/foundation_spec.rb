require "rails_helper"

# F13c: what every call of the public API shares: the token, the errors, the rate, the pages, the filters, the ETag, the isolation.
RSpec.describe "Public API foundations", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:token) { token_for(%w[accounts:read partners:read]) }

  describe "the token" do
    it "answers 401 as problem+json to a missing, unknown, revoked or expired token" do
      get "/api/v1/accounts"
      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/problem+json")
      expect(json).to include("status" => 401, "title" => "Unauthorized", "instance" => "/api/v1/accounts")
      expect(json["type"]).to start_with("https://ledgerflow.app/problems/")
      expect(response.headers["WWW-Authenticate"]).to start_with("Bearer")

      api_get("/api/v1/accounts", "lf_forgotten")
      expect(response).to have_http_status(:unauthorized)

      client = ApiClient.find_by!(key_digest: ApiClient.digest(token))
      api_get("/api/v1/accounts", token)
      expect(response).to have_http_status(:ok)
      expect(client.reload.last_used_at).to be_present
      client.update!(expires_at: 1.minute.from_now)
      travel(2.minutes) { api_get("/api/v1/accounts", token); expect(response).to have_http_status(:unauthorized) }
      client.update_columns(expires_at: nil)
      client.revoke!
      api_get("/api/v1/accounts", token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "answers 403 naming the scope that is missing, and to an entity that did not turn the API on" do
      api_get("/api/v1/journals", token)
      expect(response).to have_http_status(:forbidden)
      expect(json).to include("required_scope" => "journals:read")
      expect(json["detail"]).to include("journals:read")

      entity.update!(features: { "f13" => false })
      api_get("/api/v1/accounts", token)
      expect(response).to have_http_status(:forbidden)
    end

    it "stops serving a token whose owner lost their access to the entity, at the next call" do
      doc = token_for(%w[documents:read])
      api_get("/api/v1/documents", doc)
      expect(response).to have_http_status(:ok)

      UserEntity.find_by(user: ApiClient.find_by!(key_digest: ApiClient.digest(doc)).owner, entity: entity).update_columns(valid_until: 1.day.ago.to_date)
      api_get("/api/v1/documents", doc)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the rate" do
    it "says what is left, and answers 429 with Retry-After once the token's limit is passed" do
      Rack::Attack.cache.store.clear
      limited = token_for(%w[accounts:read], rate_limit_per_minute: 2)
      api_get("/api/v1/accounts", limited)
      expect(response.headers.to_h.transform_keys(&:downcase).slice("ratelimit-limit", "ratelimit-remaining")).to eq("ratelimit-limit" => "2", "ratelimit-remaining" => "1")
      api_get("/api/v1/accounts", limited)
      api_get("/api/v1/accounts", limited)
      expect(response).to have_http_status(:too_many_requests)
      expect(response.media_type).to eq("application/problem+json")
      expect(response.headers["Retry-After"].to_i).to be_between(1, 60)
      expect(response.headers["RateLimit-Remaining"]).to eq("0")

      api_get("/api/v1/accounts", token) # another token has its own count
      expect(response).to have_http_status(:ok)
    end
  end

  describe "collections" do
    before do
      Accounting::Account.where.not(id: [ account_604.id, account_440.id, account_400.id ]).delete_all
      account_440.update!(account_class: 4, account_type: :liability, normal_balance: :credit)
      account_400.update!(account_class: 4, account_type: :asset, normal_balance: :debit)
    end

    it "pages by cursor in a stable order, without a gap or a repeat" do
      create_list(:partner, 5).each_with_index { |p, i| p.update!(name: "Partner #{i}") }
      seen = []
      cursor = nil
      loop do
        api_get("/api/v1/partners", token, params: { page: { size: 2, after: cursor }.compact, sort: "name" })
        expect(response).to have_http_status(:ok)
        seen += json["data"].map { |p| p["name"] }
        break unless json["meta"]["has_more"]

        cursor = json["meta"]["next_cursor"]
      end
      expect(seen).to eq((0..4).map { |i| "Partner #{i}" })
    end

    it "sorts descending with a minus, and filters" do
      api_get("/api/v1/accounts", token, params: { sort: "-code" })
      expect(json["data"].map { |a| a["code"] }).to eq(%w[604000 440000 400000])
      api_get("/api/v1/accounts", token, params: { filter: { code: "44" } })
      expect(json["data"].map { |a| a["code"] }).to eq(%w[440000])
      api_get("/api/v1/accounts", token, params: { filter: { account_class: 6 } })
      expect(json["data"].map { |a| a["code"] }).to eq(%w[604000])
    end

    it "pages a descending sort too" do
      api_get("/api/v1/accounts", token, params: { sort: "-code", page: { size: 2 } })
      second = json["meta"]["next_cursor"]
      api_get("/api/v1/accounts", token, params: { sort: "-code", page: { size: 2, after: second } })
      expect(json["data"].map { |a| a["code"] }).to eq(%w[400000])
      expect(json["meta"]).to include("has_more" => false, "next_cursor" => nil)
    end

    it "refuses what it does not know: a filter, a sort, a cursor" do
      api_get("/api/v1/accounts", token, params: { filter: { colour: "red" } })
      expect(response).to have_http_status(:bad_request)
      expect(json["detail"]).to include("Known filters")
      api_get("/api/v1/accounts", token, params: { sort: "secret" })
      expect(response).to have_http_status(:bad_request)
      api_get("/api/v1/accounts", token, params: { page: { after: "garbage" } })
      expect(response).to have_http_status(:bad_request)
      expect(json["title"]).to eq("Invalid cursor")
    end

    it "gives a resource with its ETag, and answers 304 to a reader that has it" do
      api_get("/api/v1/accounts/#{account_604.id}", token)
      expect(json["data"]).to include("code" => "604000", "account_type" => "expense", "reconcilable" => false)
      etag = response.headers["ETag"]
      expect(etag).to be_present
      api_get("/api/v1/accounts/#{account_604.id}", token, headers: { "If-None-Match" => etag })
      expect(response).to have_http_status(:not_modified)
      account_604.update!(label_fr: "Changed")
      api_get("/api/v1/accounts/#{account_604.id}", token, headers: { "If-None-Match" => etag })
      expect(response).to have_http_status(:ok)
    end

    it "answers 404 for a resource that is not there" do
      api_get("/api/v1/accounts/999999", token)
      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/problem+json")
    end

    it "writes amounts as text and dates in ISO" do
      create(:bank_account).then { |b| create(:bank_transaction, bank_account: b, amount: BigDecimal("12.5"), transaction_date: Date.new(2026, 3, 1)) }
      bank = token_for(%w[bank:read])
      api_get("/api/v1/bank_transactions", bank)
      expect(json["data"].first).to include("amount" => "12.5", "transaction_date" => "2026-03-01")
    end
  end

  describe "isolation between companies" do
    it "never shows what belongs to another company, in a list or by id" do
      other = create(:entity)
      theirs = ActsAsTenant.with_tenant(other) { create(:account, code: "999999", label_fr: "Theirs", entity: other) }
      api_get("/api/v1/accounts", token)
      expect(json["data"].map { |a| a["code"] }).not_to include("999999")
      api_get("/api/v1/accounts/#{theirs.id}", token)
      expect(response).to have_http_status(:not_found)

      foreign_token = token_for(%w[accounts:read], entity: other)
      api_get("/api/v1/accounts", foreign_token)
      expect(json["data"].map { |a| a["code"] }).to eq([ "999999" ])
    end
  end
end
