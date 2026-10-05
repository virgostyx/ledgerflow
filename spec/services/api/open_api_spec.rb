require "rails_helper"

# F13c criterion 8: the OpenAPI document is valid, says what the routes do and what the answers are, and a change that breaks the published v1 fails.
RSpec.describe Api::V1::OpenApi, type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:doc) { JSON.parse(JSON.generate(described_class.document)) }
  let(:published) { JSON.parse(Rails.root.join("docs/api/openapi-v1.json").read) }

  it "is a valid OpenAPI 3.1 document: structure, parameters, references, unique operation ids" do
    expect(document_problems(doc)).to eq([])
    expect(doc["info"]["version"]).to eq("1.0.0")
  end

  it "describes every public route, and only routes that exist" do
    documented = doc["paths"].flat_map { |path, item| item.keys.map { |m| [ m.upcase, path.gsub(/\{\w+\}/, ":id") ] } }
    routed = Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      next unless controller.to_s.start_with?("api/v1/public") && route.verb != "PUT" # a PUT is the other spelling of the PATCH of the same route

      [ route.verb, route.path.spec.to_s.delete_prefix("/api/v1").sub("(.:format)", "").gsub(/:\w+/, ":id") ]
    end
    routed = routed.uniq
    expect(routed - documented).to eq([]), "routes without documentation"
    expect(documented - routed).to eq([]), "documentation without a route"
  end

  it "is served without a token, as JSON, and read by a page" do
    get "/api/v1/openapi.json"
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["openapi"]).to eq("3.1.0")
    get "/api/docs"
    expect(response.body).to include("LedgerFlow API", "listAccounts", "createEntry")
  end

  describe "contract: real answers keep to their schema" do
    let(:token) { token_for(%w[accounts:read partners:read journals:read documents:read bank:read tasks:read periods:read letterings:read entries:read entries:write entries:post reports:read]) }

    it "holds for every collection and every single resource" do
      create(:partner); create(:journal, code: "OD"); create(:document); Accounting::Task.create!(title: "T")
      Accounting::PeriodLock.create!(starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 1, 31), kind: :accounting, lock_reason: "x", locked_by: owner_with(:admin), locked_at: Time.current)
      Api::V1::Resources::REGISTRY.each_value do |resource|
        api_get("/api/v1/#{resource.name}", token)
        schema = doc.dig("paths", "/#{resource.name}", "get", "responses", "200", "content", "application/json", "schema")
        expect(schema_violations(doc, schema, json)).to eq([]), resource.name
        next if json["data"].empty?

        api_get("/api/v1/#{resource.name}/#{json['data'].first['id']}", token)
        show = doc.dig("paths", "/#{resource.name}/{id}", "get", "responses", "200", "content", "application/json", "schema")
        expect(schema_violations(doc, show, json)).to eq([]), "#{resource.name} (one)"
      end
    end

    it "holds for entries (create, read, post, reverse) and for a report" do
      create(:journal, code: "OD")
      body = { entry: { journal: "OD", entry_date: (fiscal_year.start_date + 3).iso8601, lines: [ { account: "604000", debit: "5" }, { account: "440000", credit: "5" } ] } }
      api_post("/api/v1/entries", token, body)
      created = doc.dig("paths", "/entries", "post", "responses", "201", "content", "application/json", "schema")
      expect(schema_violations(doc, created, json)).to eq([])
      id = json["data"]["id"]
      expect(schema_violations(doc, doc.dig("paths", "/entries", "post", "requestBody", "content", "application/json", "schema"), JSON.parse(body.to_json))).to eq([])

      api_get("/api/v1/entries", token)
      expect(schema_violations(doc, doc.dig("paths", "/entries", "get", "responses", "200", "content", "application/json", "schema"), json)).to eq([])
      api_post("/api/v1/entries/#{id}/post", token)
      expect(schema_violations(doc, doc.dig("paths", "/entries/{id}/post", "post", "responses", "200", "content", "application/json", "schema"), json)).to eq([])

      api_get("/api/v1/reports/trial_balance", token, params: { fiscal_year: fiscal_year.year })
      expect(schema_violations(doc, doc.dig("paths", "/reports/{name}", "get", "responses", "200", "content", "application/json", "schema"), json)).to eq([])
    end

    it "holds for the errors: they are problem+json" do
      api_get("/api/v1/accounts/0", token)
      expect(schema_violations(doc, doc.dig("components", "schemas", "Problem"), json)).to eq([])
    end

    it "notices an answer that does not keep to its schema (the validator is not blind)" do
      schema = doc.dig("components", "schemas", "Entry")
      expect(schema_violations(doc, schema, { "id" => "1", "status" => "weird" })).to include(match(/id: "1" is none of integer/), match(/status: "weird" is not in/), match(/entry_date is missing/))
    end
  end

  describe "compatibility with the published version (docs/api/openapi-v1.json)" do
    it "breaks nothing of it: no path, parameter, status or property gone, nothing new required" do
      expect(Api::V1::OpenApi::Compatibility.breaking_changes(published, doc)).to eq([])
    end

    it "knows what a break is" do
      def check(old, &change) = Api::V1::OpenApi::Compatibility.breaking_changes(old, JSON.parse(JSON.generate(old)).tap(&change))

      expect(check(doc) { |d| d["paths"].delete("/accounts") }).to include("path /accounts was removed")
      expect(check(doc) { |d| d["paths"]["/accounts"].delete("get") }).to include("path /accounts was removed").or include("GET /accounts was removed")
      expect(check(doc) { |d| d["paths"]["/accounts"]["get"]["parameters"].reject! { |p| p["name"] == "sort" } }).to include("GET /accounts: parameter sort (query) was removed")
      expect(check(doc) { |d| d["paths"]["/accounts"]["get"]["parameters"] << { "name" => "tenant", "in" => "query", "required" => true, "schema" => { "type" => "string" } } })
        .to include("GET /accounts: parameter tenant (query) became required")
      expect(check(doc) { |d| d["paths"]["/accounts"]["get"]["responses"].delete("403") }).to include("GET /accounts: response 403 was removed")
      expect(check(doc) { |d| d["components"]["schemas"]["Account"]["properties"].delete("code") }).to include(match(/property code was removed/))
      expect(check(doc) { |d| d["components"]["schemas"]["Account"]["properties"]["code"] = { "type" => "integer" } }).to include(match(/type string\|null became integer/))
      expect(check(doc) { |d| d["components"]["schemas"]["Entry"]["properties"]["status"]["enum"].delete("posted") }).to include(match(/enum values removed \(posted\)/))
      expect(check(doc) { |d| d["components"]["schemas"]["EntryInput"]["properties"]["entry"]["required"] << "journal" }).to include(match(/property journal became required/))
      expect(check(doc) { |d| d["paths"]["/entries/{id}/post"]["post"]["x-required-scope"] = "entries:read" }).to include(match(/the scope changed/))
    end

    it "lets what is added through" do
      added = JSON.parse(JSON.generate(doc)).tap do |d|
        d["paths"]["/new_resource"] = d["paths"]["/accounts"]
        d["paths"]["/accounts"]["get"]["parameters"] << { "name" => "extra", "in" => "query", "schema" => { "type" => "string" } }
        d["paths"]["/accounts"]["get"]["responses"]["418"] = { "description" => "teapot" }
        d["components"]["schemas"]["Account"]["properties"]["extra"] = { "type" => "string" }
      end
      expect(Api::V1::OpenApi::Compatibility.breaking_changes(doc, added)).to eq([])
    end
  end
end
