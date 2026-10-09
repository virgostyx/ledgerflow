require "rails_helper"

# B01a through the API: what waits for the owner of the token, one request with its circuit, and a decision. The same circuit as the screens:
# the fingerprint of the content seen, separation of tasks, one decision per level, everything in the audit trail.
RSpec.describe "Public API approvals", type: :request do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:author)      { create(:user) }
  let(:account)     { create(:account) }
  let!(:policy) do
    Approvals::Policy.create!(name: "all", subject: :purchase_invoice, priority: 1).tap do |p|
      p.steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin accountant])
    end
  end
  let(:token)   { token_for(%w[approvals:read approvals:decide], role: :accountant) }
  let(:owner)   { ApiClient.find_by!(key_digest: ApiClient.digest(token)).owner }

  def invoice_of(amount, partner: create(:partner, name: "Acme #{SecureRandom.hex(2)}"), due: Date.current + 10)
    create(:invoice, :supplier, partner: partner, due_date: due, created_by: author, fiscal_year: fiscal_year).tap do |i|
      create(:invoice_line, invoice: i, account: account, unit_price: amount, description: "Consulting")
    end
  end

  def submit(invoice) = Approvals::Submit.call(invoice: invoice, user: author)[:request]

  def decide(request, body, token: self.token, headers: {}) = api_post("/api/v1/approvals/#{request.id}/decision", token, body, headers: headers)

  before { owner }

  describe "the scopes" do
    it "are within the rights of the owner: someone who cannot approve cannot hold them" do
      client = ApiClient.new(entity: entity, name: "x", scopes: %w[approvals:read], owner: owner_with(:assistant), key_digest: "x")

      expect(client).not_to be_valid
      expect(client.errors.full_messages.join).to match(/approvals:read/)
    end

    it "separate reading from deciding" do
      request = submit(invoice_of("100.00"))
      reader = token_for(%w[approvals:read], role: :accountant)

      api_get("/api/v1/approvals", reader)
      expect(response).to have_http_status(:ok)

      decide(request, { decision: "approved", content_fingerprint: request.content_fingerprint }, token: reader)
      expect(response).to have_http_status(:forbidden)
      expect(json["required_scope"]).to eq("approvals:decide")
      expect(request.reload).to be_pending
    end

    it "are closed while the feature is off" do
      entity.update!(features: entity.features.merge("b01a" => false))

      api_get("/api/v1/approvals", token)

      expect(response).to have_http_status(:forbidden)
      expect(json["type"]).to end_with("approvals-not-enabled")
    end
  end

  describe "the list" do
    it "gives what waits for the owner of the token, and nothing else" do
      mine = submit(invoice_of("100.00", partner: create(:partner, name: "Mine SA")))
      other_policy = Approvals::Policy.create!(name: "elsewhere", subject: :purchase_invoice, priority: 0, conditions: { "min_amount" => "5000" })
      other_policy.steps.create!(position: 1, mode: :any_of, approver_user_ids: [ create(:user_entity, :admin, entity: entity).user_id ])
      submit(invoice_of("9000.00"))
      done = submit(invoice_of("300.00")).tap { |r| Approvals::Decide.call(request: r, user: owner, decision: :approved, content_fingerprint: r.content_fingerprint) }

      api_get("/api/v1/approvals", token)

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |r| r["id"] }).to eq([ mine.id ])
      expect(json["data"].first).to include("status" => "pending", "level" => 1, "content_fingerprint" => mine.content_fingerprint,
                                            "invoice" => a_hash_including("supplier" => "Mine SA", "currency" => "EUR", "amount_incl_vat" => "121.00", "amount_eur" => "121.00"))
      expect(json["data"].map { |r| r["id"] }).not_to include(done.id)
    end

    it "pages by cursor and filters by supplier" do
      3.times { |n| submit(invoice_of("100.00", partner: create(:partner, name: n.zero? ? "Needle Co" : "Hay #{n}"))) }

      api_get("/api/v1/approvals", token, params: { page: { size: 2 } })
      expect(json["data"].size).to eq(2)
      expect(json["meta"]).to include("has_more" => true)
      api_get("/api/v1/approvals", token, params: { page: { size: 2, after: json["meta"]["next_cursor"] } })
      expect(json["data"].size).to eq(1)

      api_get("/api/v1/approvals", token, params: { filter: { supplier: "needle" } })
      expect(json["data"].map { |r| r["invoice"]["supplier"] }).to eq([ "Needle Co" ])
    end

    it "refuses a filter it does not know" do
      api_get("/api/v1/approvals", token, params: { filter: { colour: "red" } })

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "one request" do
    let(:invoice) { invoice_of("1000.00", partner: create(:partner, name: "Acme Ltd")) }
    let!(:request_record) { submit(invoice) }

    it "gives the invoice with its lines, the circuit with the decisions, the warnings, and its ETag" do
      api_get("/api/v1/approvals/#{request_record.id}", token)

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).to be_present
      data = json["data"]
      expect(data).to include("id" => request_record.id, "can_decide" => true, "content_fingerprint" => request_record.content_fingerprint, "warnings" => [])
      expect(data["invoice"]).to include("supplier" => "Acme Ltd", "amount_incl_vat" => "1210.00")
      expect(data["invoice"]["lines"]).to eq([ { "account" => account.code, "description" => "Consulting", "amount_incl_vat" => "1210.00" } ])
      expect(data["levels"]).to eq([ { "position" => 1, "mode" => "any_of", "current" => true, "decisions" => [] } ])
    end

    it "shows a decision with who took it and by which channel" do
      decide(request_record, { decision: "approved", content_fingerprint: request_record.content_fingerprint })

      api_get("/api/v1/approvals/#{request_record.id}", token)

      expect(json["data"]).to include("status" => "approved", "can_decide" => false)
      expect(json["data"]["levels"].first["decisions"].first).to include("decision" => "approved", "approver" => owner.full_name, "channel" => "api")
    end

    it "is not found for a request that is not for this owner and was never decided by them" do
      request_record.update!(policy: Approvals::Policy.create!(name: "x", subject: :purchase_invoice, priority: 0).tap { |p| p.steps.create!(position: 1, mode: :any_of, approver_user_ids: [ create(:user_entity, :admin, entity: entity).user_id ]) })

      api_get("/api/v1/approvals/#{request_record.id}", token)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a decision" do
    let!(:request_record) { submit(invoice_of("1000.00")) }
    let(:seen) { { content_fingerprint: request_record.content_fingerprint } }

    it "approves on the content seen, through the circuit, from the api channel" do
      decide(request_record, seen.merge(decision: "approved"))

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("status" => "approved")
      expect(request_record.reload).to be_approved
      expect(request_record.subject.reload).to be_payment_approved
      decision = request_record.decisions.sole
      expect(decision).to have_attributes(approver: owner, channel: "api", content_fingerprint: request_record.content_fingerprint)
      expect(Accounting::AuditLog.for_record(request_record.subject).for_action("approval_approved").last.payload).to include("channel" => "api")
    end

    it "refuses with a reason and asks for changes with one, not without" do
      decide(request_record, seen.merge(decision: "rejected"))
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["type"]).to end_with("reason-required")

      decide(request_record, seen.merge(decision: "changes_requested", comment: "Add the PO number"))
      expect(response).to have_http_status(:ok)
      expect(request_record.reload).to be_changes_requested
    end

    it "refuses an unknown decision" do
      decide(request_record, seen.merge(decision: "maybe"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["type"]).to end_with("unknown-decision")
    end

    it "is refused with 409 when the invoice is not as it was read" do
      decide(request_record, { decision: "approved", content_fingerprint: "0" * 64 })

      expect(response).to have_http_status(:conflict)
      expect(json["type"]).to end_with("content-changed")
      expect(request_record.reload).to be_pending
    end

    it "is refused with 409 when the invoice changed after it was read (the request was invalidated)" do
      request_record.subject.lines.first.update!(unit_price: "5000.00")

      decide(request_record, seen.merge(decision: "approved"))

      expect(response).to have_http_status(:conflict)
      expect(json["type"]).to end_with("content-changed")
    end

    it "is refused to the author of the invoice, who may not approve their own" do
      author_token = token_for(%w[approvals:read approvals:decide], role: :admin)
      client = ApiClient.find_by!(key_digest: ApiClient.digest(author_token))
      request_record.subject.update_columns(created_by_id: client.owner_id)

      decide(request_record, seen.merge(decision: "approved"), token: author_token)

      expect(response).to have_http_status(:forbidden)
      expect(json["type"]).to end_with("separation-of-duties")
      expect(request_record.reload).to be_pending
    end

    it "answers 409 once the request is decided" do
      decide(request_record, seen.merge(decision: "approved"))
      decide(request_record, seen.merge(decision: "approved"))

      expect(response).to have_http_status(:conflict)
      expect(json["type"]).to end_with("already-decided")
    end

    it "gives the same answer to the same Idempotency-Key, and decides once" do
      2.times { decide(request_record, seen.merge(decision: "approved"), headers: { "Idempotency-Key" => "abc-1" }) }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Idempotent-Replayed"]).to eq("true")
      expect(request_record.decisions.count).to eq(1)
    end

    it "is written in the audit trail as an API write, with the token" do
      decide(request_record, seen.merge(decision: "approved"))

      log = Accounting::AuditLog.where(action: "api_write").last
      expect(log.payload).to include("http_method" => "POST", "path" => "/api/v1/approvals/#{request_record.id}/decision", "status" => 200)
    end
  end
end
