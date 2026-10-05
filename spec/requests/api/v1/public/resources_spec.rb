require "rails_helper"

# F13c: every resource of the registry answers in its own scope, in the same shape; the reports give the Reports::Result as JSON.
RSpec.describe "Public API resources", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  it "serves each resource of the registry to a token with its scope, and refuses it to one without" do
    Api::V1::Resources::REGISTRY.each_value do |resource|
      api_get("/api/v1/#{resource.name}", token_for([ resource.scope ]))
      expect(response).to have_http_status(:ok), "#{resource.name}: #{response.body}"
      expect(json).to include("data" => be_an(Array), "meta" => include("has_more" => false))

      api_get("/api/v1/#{resource.name}", token_for(resource.scope == "accounts:read" ? %w[journals:read] : %w[accounts:read]))
      expect(response).to have_http_status(:forbidden), resource.name
      expect(json["required_scope"]).to eq(resource.scope)
    end
  end

  it "shows what is there, in the shape of the registry" do
    partner = create(:partner, name: "Acme", vat_number: "BE0417497106")
    journal = create(:journal, code: "OD")
    task = Accounting::Task.create!(title: "Call", due_on: Date.new(2026, 4, 1))
    lock = Accounting::PeriodLock.create!(starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 1, 31), kind: :vat, lock_reason: "Filed", locked_by: owner_with(:admin), locked_at: Time.current)
    document = create(:document, name: "a.pdf")
    statement_account = create(:bank_account)

    expectations = { "partners" => [ partner, "name" => "Acme", "vat_number" => "BE0417497106" ], "journals" => [ journal, "code" => "OD" ],
                     "tasks" => [ task, "title" => "Call", "due_on" => "2026-04-01", "status" => "open" ],
                     "period_locks" => [ lock, "starts_on" => "2026-01-01", "kind" => "vat", "lock_reason" => "Filed" ],
                     "documents" => [ document, "name" => "a.pdf", "sha256" => document.sha256 ] }
    expectations.each do |name, (record, attributes)|
      token = token_for([ Api::V1::Resources::REGISTRY.fetch(name).scope ])
      api_get("/api/v1/#{name}/#{record.id}", token)
      expect(json["data"]).to include(attributes), name
    end
    expect(statement_account).to be_persisted
  end

  describe "reports" do
    let(:reader) { token_for(%w[reports:read], role: :manager) }

    it "gives the trial balance as the Reports::Result of the screen, amounts as text" do
      entry = create(:journal_entry, :draft, journal: create(:journal, code: "OD"), fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 1)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: 10, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: account_440, debit: 0, credit: 10)
      Accounting::PostJournalEntry.call!(entry: entry)

      api_get("/api/v1/reports/trial_balance", reader, params: { fiscal_year: fiscal_year.year })
      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("report" => "trial_balance", "currency" => "EUR")
      row = json["data"]["rows"].find { |r| r["code"] == "604000" }
      expect(row).to include("movement_debit" => "10.0")
      expect(json["data"]["generated_at"]).to be_present
    end

    it "gives the aged balance" do
      api_get("/api/v1/reports/aged_balance", reader, params: { kind: "customer", as_of: "2026-06-30" })
      expect(json["data"]).to include("report" => "aged_balance", "rows" => [])
      expect(json["data"]["totals"]).to include("total" => "0.0")
    end

    it "refuses an unknown report, and needs its scope" do
      api_get("/api/v1/reports/secrets", reader)
      expect(response).to have_http_status(:not_found)
      api_get("/api/v1/reports/trial_balance", token_for(%w[accounts:read]))
      expect(response).to have_http_status(:forbidden)
    end
  end
end
