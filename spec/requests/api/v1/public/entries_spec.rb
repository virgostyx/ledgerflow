require "rails_helper"

# F13c: entries through the API. Drafts by default, validation an explicit action that needs the right, no change to a validated entry, and the
# protections of a write: Idempotency-Key, ETag and If-Match.
RSpec.describe "Public API entries", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:journal) { create(:journal, code: "OD", journal_type: :misc) }
  let(:day)      { (fiscal_year.start_date + 10).iso8601 }
  let(:writer)   { token_for(%w[entries:read entries:write entries:post entries:reverse], role: :accountant) }
  let(:body) do
    { entry: { journal: "OD", entry_date: day, description: "Rent", external_id: "ERP-1",
               lines: [ { account: "604000", debit: "100.00", label: "Rent" }, { account: "440000", credit: "100.00", label: "Landlord" } ] } }
  end

  def create_entry(token = writer, payload = body, headers: {}) = api_post("/api/v1/entries", token, payload, headers: headers)

  describe "creating" do
    it "makes a draft, 201 with its place and its ETag, and writes it in the audit trail" do
      expect { create_entry }.to change(Accounting::JournalEntry, :count).by(1)

      expect(response).to have_http_status(:created)
      entry = Accounting::JournalEntry.last
      expect(response.headers["Location"]).to eq("/api/v1/entries/#{entry.id}")
      expect(response.headers["ETag"]).to be_present
      expect(json["data"]).to include("status" => "draft", "reference" => nil, "journal" => "OD", "entry_date" => day, "external_id" => "ERP-1", "fiscal_year" => fiscal_year.year)
      expect(json["data"]["lines"].map { |l| l.slice("account", "debit", "credit") }).to eq([ { "account" => "604000", "debit" => "100.00", "credit" => "0.00" },
                                                                                             { "account" => "440000", "debit" => "0.00", "credit" => "100.00" } ])
      expect(entry).to have_attributes(status: "draft", created_by: ApiClient.find_by!(key_digest: ApiClient.digest(writer)).owner)
      log = Accounting::AuditLog.where(action: "api_write").last
      expect(log.payload).to include("http_method" => "POST", "path" => "/api/v1/entries", "status" => 201, "token" => "Test token")
    end

    it "refuses an entry that does not balance, an unknown account or journal, a date outside the open years, and a foreign line" do
      create_entry(writer, { entry: body[:entry].merge(lines: [ { account: "604000", debit: "100" }, { account: "440000", credit: "90" } ]) })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["detail"]).to match(/balance/i)

      create_entry(writer, { entry: body[:entry].merge(lines: [ { account: "999999", debit: "1" }, { account: "440000", credit: "1" } ]) })
      expect(json["detail"]).to include("account 999999 is unknown")
      create_entry(writer, { entry: body[:entry].merge(journal: "NOPE") })
      expect(json["detail"]).to include("journal NOPE is unknown")
      create_entry(writer, { entry: body[:entry].merge(entry_date: (fiscal_year.end_date + 9).iso8601) })
      expect(json["detail"]).to match(/no open fiscal year/i)
      create_entry(writer, { entry: body[:entry].merge(lines: [ { account: "604000", debit: "1", currency: "USD" }, { account: "440000", credit: "1" } ]) })
      expect(json["detail"]).to match(/EUR/)
      expect(Accounting::JournalEntry.count).to eq(0)
    end

    it "does not create a second entry for an external id already used" do
      create_entry
      expect { create_entry }.not_to change(Accounting::JournalEntry, :count)
      expect(response).to have_http_status(:conflict)
      expect(json["title"]).to eq("Already exists")
    end

    it "is closed to a token that may not write: no scope, or an owner who may not" do
      create_entry(token_for(%w[entries:read]))
      expect(response).to have_http_status(:forbidden)
      expect(json["required_scope"]).to eq("entries:write")
      expect(Accounting::JournalEntry.count).to eq(0)
    end

    it "keeps to the journals its owner may use" do
      owner = owner_with(:accountant)
      UserEntity.find_by(user: owner, entity: entity).update!(journal_ids: [ create(:journal, code: "ZZ").id ])
      restricted = ApiClient.issue!(entity: entity, name: "Restricted", scopes: %w[entries:write], owner: owner).last
      create_entry(restricted)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Idempotency-Key (criterion 5)" do
    it "gives the same answer to the same request and creates nothing more" do
      create_entry(writer, body, headers: { "Idempotency-Key" => "key-1" })
      first = response.body
      first_location = response.headers["Location"]
      expect(response).to have_http_status(:created)

      expect { create_entry(writer, body, headers: { "Idempotency-Key" => "key-1" }) }.not_to change(Accounting::JournalEntry, :count)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)).to eq(JSON.parse(first))
      expect(response.headers["Location"]).to eq(first_location)
      expect(response.headers["Idempotent-Replayed"]).to eq("true")
      expect(ApiIdempotencyKey.count).to eq(1)
    end

    it "refuses the key for another request, and says a first request is still running" do
      create_entry(writer, body, headers: { "Idempotency-Key" => "key-2" })
      create_entry(writer, { entry: body[:entry].merge(description: "Other") }, headers: { "Idempotency-Key" => "key-2" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["title"]).to eq("Idempotency key reused")

      client = ApiClient.find_by!(key_digest: ApiClient.digest(writer))
      ApiIdempotencyKey.create!(api_client: client, key: "key-3", request_fingerprint: Digest::SHA256.hexdigest([ "POST", "/api/v1/entries", body.to_json ].join("\n")))
      create_entry(writer, body, headers: { "Idempotency-Key" => "key-3" })
      expect(response).to have_http_status(:conflict)
    end

    it "keeps a key per token, and forgets the key of a request that failed on the server" do
      other = token_for(%w[entries:write])
      create_entry(writer, body, headers: { "Idempotency-Key" => "same" })
      create_entry(other, { entry: body[:entry].merge(external_id: "ERP-2") }, headers: { "Idempotency-Key" => "same" })
      expect(response).to have_http_status(:created)

      allow(Accounting::JournalEntry).to receive(:new).and_raise("boom")
      expect { create_entry(writer, body, headers: { "Idempotency-Key" => "again" }) }.to raise_error("boom")
      expect(ApiIdempotencyKey.where(key: "again")).to be_empty
    end

    it "forgets old keys" do
      client = ApiClient.find_by!(key_digest: ApiClient.digest(writer))
      old = ApiIdempotencyKey.create!(api_client: client, key: "old", request_fingerprint: "x", response_status: 201, created_at: 2.days.ago)
      fresh = ApiIdempotencyKey.create!(api_client: client, key: "fresh", request_fingerprint: "x", response_status: 201)
      ActsAsTenant.without_tenant { Api::PurgeIdempotencyKeysJob.perform_now }
      expect(ApiIdempotencyKey.where(id: [ old.id, fresh.id ])).to eq([ fresh ])
    end
  end

  describe "validating (criterion 6)" do
    before { create_entry }
    let(:entry) { Accounting::JournalEntry.last }

    it "is an explicit action: the entry is a draft until it is asked" do
      expect(entry).to be_draft
      api_post("/api/v1/entries/#{entry.id}/post", writer)
      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("status" => "posted")
      expect(json["data"]["reference"]).to be_present
    end

    it "is refused with 403 to a token without the scope, and to an owner who may not validate" do
      api_post("/api/v1/entries/#{entry.id}/post", token_for(%w[entries:read entries:write]))
      expect(response).to have_http_status(:forbidden)
      expect(json["required_scope"]).to eq("entries:post")

      accountant_token = writer
      UserEntity.find_by(user: ApiClient.find_by!(key_digest: ApiClient.digest(accountant_token)).owner, entity: entity).update!(role: :assistant)
      api_post("/api/v1/entries/#{entry.id}/post", accountant_token)
      expect(response).to have_http_status(:forbidden)
      expect(entry.reload).to be_draft
    end

    it "is refused in a locked period, with the reason of the lock" do
      Accounting::PeriodLock.create!(starts_on: fiscal_year.start_date, ends_on: fiscal_year.end_date, kind: :accounting, lock_reason: "Year filed", locked_by: owner_with(:admin), locked_at: Time.current)
      api_post("/api/v1/entries/#{entry.id}/post", writer)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["detail"]).to match(/locked/i)
    end

    it "keeps the four-eyes rule: the author may not validate their own entry when the entity asks for a second person" do
      entity.update!(four_eyes: true)
      api_post("/api/v1/entries/#{entry.id}/post", writer)
      expect(response).to have_http_status(:forbidden)
      expect(json["title"]).to eq("Four eyes")
    end
  end

  describe "changing: ETag and If-Match" do
    let!(:created) { create_entry; Accounting::JournalEntry.last }

    it "wants the ETag back: 428 without it, 412 when it is stale, and a new ETag when it was current" do
      etag = response.headers["ETag"]
      api_patch("/api/v1/entries/#{created.id}", writer, { entry: { description: "No precondition" } })
      expect(response).to have_http_status(:precondition_required)

      api_patch("/api/v1/entries/#{created.id}", writer, { entry: { description: "Changed" } }, headers: { "If-Match" => etag })
      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).not_to eq(etag)
      expect(created.reload.description).to eq("Changed")

      api_patch("/api/v1/entries/#{created.id}", writer, { entry: { description: "Second writer" } }, headers: { "If-Match" => etag })
      expect(response).to have_http_status(:precondition_failed)
      expect(created.reload.description).to eq("Changed")
    end

    it "notices a change of the lines too, and replaces the lines when it is sent new ones" do
      etag = response.headers["ETag"]
      lines = [ { account: "604000", debit: "40.00" }, { account: "440000", credit: "40.00" } ]
      api_patch("/api/v1/entries/#{created.id}", writer, { entry: { lines: lines } }, headers: { "If-Match" => etag })
      expect(response).to have_http_status(:ok)
      expect(created.reload.lines.sum(:debit)).to eq(40)

      api_get("/api/v1/entries/#{created.id}", writer)
      expect(response.headers["ETag"]).not_to eq(etag)
    end

    it "never changes a validated entry: it is reversed" do
      api_post("/api/v1/entries/#{created.id}/post", writer)
      api_get("/api/v1/entries/#{created.id}", writer)
      api_patch("/api/v1/entries/#{created.id}", writer, { entry: { description: "Late" } }, headers: { "If-Match" => response.headers["ETag"] })
      expect(response).to have_http_status(:conflict)
      expect(json["detail"]).to match(/reverse/i)
      expect(created.reload.description).to eq("Rent")
    end

    it "refuses an unbalanced change and leaves the entry as it was" do
      etag = response.headers["ETag"]
      api_patch("/api/v1/entries/#{created.id}", writer, { entry: { lines: [ { account: "604000", debit: "1" }, { account: "440000", credit: "2" } ] } }, headers: { "If-Match" => etag })
      expect(response).to have_http_status(:unprocessable_content)
      expect(created.reload.lines.sum(:debit)).to eq(100)
    end
  end

  describe "reversing" do
    it "reverses a validated entry with a reason, through the service of the application" do
      create_entry
      entry = Accounting::JournalEntry.last
      api_post("/api/v1/entries/#{entry.id}/post", writer)

      api_post("/api/v1/entries/#{entry.id}/reverse", writer, { reason: "Wrong tenant" })
      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("status" => "posted")
      expect(json["data"]["description"]).to be_present
      expect(entry.reload).to be_reversed

      api_post("/api/v1/entries/#{entry.id}/reverse", writer, { reason: "Again" })
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "needs its own scope, and a draft is not reversed" do
      create_entry
      entry = Accounting::JournalEntry.last
      api_post("/api/v1/entries/#{entry.id}/reverse", token_for(%w[entries:write entries:post]), { reason: "x" })
      expect(response).to have_http_status(:forbidden)
      api_post("/api/v1/entries/#{entry.id}/reverse", writer, { reason: "x" })
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "reading" do
    it "lists with filters and shows an entry with its lines, never another company's" do
      create_entry
      create_entry(writer, { entry: body[:entry].merge(external_id: "ERP-2", entry_date: (fiscal_year.start_date + 30).iso8601) })
      api_get("/api/v1/entries", writer, params: { filter: { from: (fiscal_year.start_date + 20).iso8601 } })
      expect(json["data"].map { |e| e["external_id"] }).to eq(%w[ERP-2])
      api_get("/api/v1/entries", writer, params: { filter: { status: "draft", journal: "OD" }, sort: "-entry_date" })
      expect(json["data"].map { |e| e["external_id"] }).to eq(%w[ERP-2 ERP-1])
      expect(json["data"].first["lines"].size).to eq(2)

      other = create(:entity)
      theirs = ActsAsTenant.with_tenant(other) { create(:journal_entry, :draft, journal: create(:journal, entity: other), fiscal_year: create(:fiscal_year, entity: other), entry_date: Date.current) }
      api_get("/api/v1/entries/#{theirs.id}", writer)
      expect(response).to have_http_status(:not_found)
    end
  end
end
