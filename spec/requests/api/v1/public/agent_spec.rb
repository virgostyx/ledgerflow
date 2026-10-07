require "rails_helper"

# A01: the agent through the public API. The same permissions, the same entity, the same checks as the panel (the assistant on, the terms accepted, the right, the quotas, what a person types
# reviewed first). The answer is written in the background: a question is accepted (202) and the conversation is read until it is no longer answering.
RSpec.describe "Public API agent", type: :request do
  include_context "with_open_fiscal_year"

  let(:token) { token_for(%w[agent:use], role: :accountant) }
  let(:owner) { ApiClient.find_by!(key_digest: ApiClient.digest(token)).owner }
  let(:doc) { JSON.parse(JSON.generate(Api::V1::OpenApi.document)) }
  let(:iban) { "BE68539007547034" }

  around do |example|
    previous = ENV.delete("AGENT_KILL_SWITCH")
    example.run
  ensure
    previous ? ENV["AGENT_KILL_SWITCH"] = previous : ENV.delete("AGENT_KILL_SWITCH")
  end

  before { enable_agent! }

  def conversation_of(user = owner, **attrs) = Agent::Conversation.create!({ user: user, title: "Mine" }.merge(attrs))

  def create_conversation(body = {}) = api_post("/api/v1/agent/conversations", token, body)

  def ask(conversation, body, headers: {}) = api_post("/api/v1/agent/conversations/#{conversation.id}/messages", token, body, headers: headers)

  def violations(schema_path, status = "200") = schema_violations(doc, doc.dig(*schema_path, "responses", status, "content", "application/json", "schema"), json)

  describe "who may" do
    it "needs the scope agent:use, and says which one it lacks" do
      api_get("/api/v1/agent/conversations", token_for(%w[entries:read]))

      expect(response).to have_http_status(:forbidden)
      expect(json["required_scope"]).to eq("agent:use")
    end

    it "is closed, with the reason in words, when the assistant is off for the entity, or the terms were not accepted" do
      Agent::Setting.for_current_entity.update!(enabled: false)
      api_get("/api/v1/agent/conversations", token)
      expect(response).to have_http_status(:forbidden)
      expect(json).to include("type" => end_with("agent-not-enabled"))
      expect(response.media_type).to eq("application/problem+json")

      Agent::Setting.for_current_entity.update!(enabled: true)
      Agent::Consent.delete_all
      api_get("/api/v1/agent/conversations", token)
      expect(json["detail"]).to include("terms")
    end

    it "is closed by the emergency switch, with a 503, on the next call" do
      api_get("/api/v1/agent/conversations", token)
      expect(response).to have_http_status(:ok)

      ENV["AGENT_KILL_SWITCH"] = "1"
      api_get("/api/v1/agent/conversations", token)

      expect(response).to have_http_status(:service_unavailable)
    end

    it "follows the right of the owner of the token: take it away and the token stops working for the agent" do
      token
      UserEntity.find_by!(user: owner).update!(role: :auditor, valid_until: 1.month.from_now)

      api_get("/api/v1/agent/conversations", token)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "conversations" do
    it "opens one for the owner of the token, in the entity of the token, on a screen and an object it is given" do
      create_conversation(conversation: { screen: "reports/aged_balance", subject_type: "R04", subject_id: "p-1" })

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to eq("/api/v1/agent/conversations/#{Agent::Conversation.last.id}")
      expect(Agent::Conversation.last).to have_attributes(user: owner, entity: entity, origin_screen: "reports/aged_balance", context_ref: { "type" => "R04", "id" => "p-1" })
      expect(json["data"]).to include("status" => "active", "answering" => false)
      expect(violations([ "paths", "/agent/conversations", "post" ], "201")).to eq([])
    end

    it "refuses a screen or an object that is not shaped like one" do
      create_conversation(conversation: { screen: "<script>" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(Agent::Conversation.count).to eq(0)
    end

    it "lists the conversations of the owner of the token only, a page at a time" do
      3.times { |i| conversation_of(title: "c#{i}") }
      conversation_of(create(:user), title: "someone else's")

      api_get("/api/v1/agent/conversations", token, params: { page: { size: 2 } })

      expect(json["data"].size).to eq(2)
      expect(json["meta"]).to include("has_more" => true)
      expect(json.to_json).not_to include("someone else's")
      expect(violations([ "paths", "/agent/conversations", "get" ])).to eq([])
    end

    it "reads one with what was said, the names as the person read them, and an ETag" do
      conversation = conversation_of
      conversation.pseudonym_table.token_for("Alice Dupont", "person")
      conversation.messages.create!(role: "user", content: "Who owes me?")
      answer = conversation.messages.create!(role: "assistant", content: "PERSONNE_001 owes 10.00 EUR.", flags: [ "suspicious_content" ])

      api_get("/api/v1/agent/conversations/#{conversation.id}", token)

      expect(response.headers["ETag"]).to be_present
      expect(json["data"]["messages"].map { |m| [ m["role"], m["content"] ] }).to eq([ [ "user", "Who owes me?" ], [ "assistant", "Alice Dupont owes 10.00 EUR." ] ])
      expect(json["data"]["messages"].last).to include("id" => answer.id, "flags" => [ "suspicious_content" ], "status" => "complete")
      expect(violations([ "paths", "/agent/conversations/{id}", "get" ])).to eq([])
    end

    it "says it is answering while it is" do
      conversation = conversation_of.tap(&:start_answering!)

      api_get("/api/v1/agent/conversations/#{conversation.id}", token)

      expect(json["data"]["answering"]).to be true
    end

    it "does not give a conversation of someone else, or of another entity" do
      theirs = conversation_of(create(:user))
      foreign = ActsAsTenant.with_tenant(create(:entity)) { Agent::Conversation.create!(user: owner, title: "elsewhere") }

      [ theirs, foreign ].each do |other|
        api_get("/api/v1/agent/conversations/#{other.id}", token)
        expect(response).to have_http_status(:not_found)
        expect(response.media_type).to eq("application/problem+json")
      end
    end

    it "renames and archives, with the ETag in If-Match, and no blind overwrite" do
      conversation = conversation_of
      api_get("/api/v1/agent/conversations/#{conversation.id}", token)
      etag = response.headers["ETag"]

      api_patch("/api/v1/agent/conversations/#{conversation.id}", token, { title: "Renamed" })
      expect(response).to have_http_status(:precondition_required)

      api_patch("/api/v1/agent/conversations/#{conversation.id}", token, { title: "Renamed", archived: true }, headers: { "If-Match" => etag })
      expect(response).to have_http_status(:ok)
      expect(conversation.reload).to have_attributes(title: "Renamed", status: "archived")

      api_patch("/api/v1/agent/conversations/#{conversation.id}", token, { title: "Again" }, headers: { "If-Match" => etag })
      expect(response).to have_http_status(:precondition_failed)
    end

    it "deletes the conversation and what was said in it" do
      conversation = conversation_of
      conversation.messages.create!(role: "user", content: "x")

      expect { api_delete("/api/v1/agent/conversations/#{conversation.id}", token) }.to change(Agent::Message, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "stops what is being answered" do
      conversation = conversation_of

      api_post("/api/v1/agent/conversations/#{conversation.id}/stop", token)

      expect(response).to have_http_status(:no_content)
      expect(conversation.reload.stop_requested_at).to be_present
    end
  end

  describe "a question" do
    let(:conversation) { conversation_of(title: nil) }

    it "is accepted: 202, the conversation marked as answering, the answer written in the background" do
      expect { ask(conversation, { question: "Who owes me the most?" }) }.to have_enqueued_job(Agent::AnswerJob).with(conversation, "Who owes me the most?", "en")

      expect(response).to have_http_status(:accepted)
      expect(response.headers["Location"]).to eq("/api/v1/agent/conversations/#{conversation.id}")
      expect(json["data"]).to eq("conversation_id" => conversation.id, "status" => "answering")
      expect(conversation.reload).to have_attributes(answering_since: be_present, title: start_with("Who owes me the most"))
      expect(violations([ "paths", "/agent/conversations/{id}/messages", "post" ], "202")).to eq([])
    end

    it "is accepted once however many times it is sent with the same Idempotency-Key" do
      expect do
        2.times { ask(conversation, { question: "Who owes me the most?" }, headers: { "Idempotency-Key" => "q-1" }) }
      end.to have_enqueued_job(Agent::AnswerJob).exactly(:once)

      expect(response.headers["Idempotent-Replayed"]).to eq("true")
    end

    it "refuses an empty or very long question, and a conversation that is archived" do
      expect do
        ask(conversation, { question: " " })
        expect(response).to have_http_status(:unprocessable_content)
        ask(conversation, { question: "x" * 4001 })
        expect(json["detail"]).to include("4000")
        conversation.archive!
        ask(conversation, { question: "Hello" })
        expect(response).to have_http_status(:unprocessable_content)
      end.not_to have_enqueued_job(Agent::AnswerJob)
    end

    it "is refused, with what was found, when it holds an IBAN, until the caller confirms; then it is masked as for a person" do
      expect { ask(conversation, { question: "Pay #{iban}" }) }.not_to have_enqueued_job(Agent::AnswerJob)
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["type"]).to end_with("sensitive-data")
      expect(json["findings"]).to eq([ { "kind" => "iban", "effect" => "mask", "count" => 1 } ])
      expect(response.body).not_to include(iban)

      expect { ask(conversation, { question: "Pay #{iban}", confirm_sensitive: true }) }.to have_enqueued_job(Agent::AnswerJob)
    end

    it "is refused even when confirmed if the entity never lets it go, and for a card number or a password" do
      Agent::Setting.for_current_entity.update!(data_class_modes: { "bank_identifier" => "block" })

      expect { ask(conversation, { question: "Pay #{iban}", confirm_sensitive: true }) }.not_to have_enqueued_job(Agent::AnswerJob)
      expect(json["type"]).to end_with("sensitive-data-blocked")
      expect { ask(conversation, { question: "card 4111 1111 1111 1111", confirm_sensitive: true }) }.not_to have_enqueued_job(Agent::AnswerJob)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "stops at the quota, saying which, with a 429" do
      allow(Agent::Config).to receive(:quotas).and_return({ per_hour: 1, per_day: 100, concurrent_per_entity: 3 })
      conversation.messages.create!(role: "user", content: "earlier")

      expect { ask(conversation, { question: "One too many" }) }.not_to have_enqueued_job(Agent::AnswerJob)

      expect(response).to have_http_status(:too_many_requests)
      expect(json["type"]).to end_with("agent-quota")
      expect(json["detail"]).to include("1 questions per hour")
    end

    it "does not keep the question in the audit trail of the call, nor in the log of the request" do
      ask(conversation, { question: "Secret question about Alice Dupont" })

      expect(Accounting::AuditLog.where(action: "api_write").to_a.map { |log| log.payload.to_json }.join).not_to include("Alice")
      expect(ApiRequest.all.map(&:path).join).not_to include("Alice")
    end

    it "does not answer in a conversation of someone else" do
      expect { ask(conversation_of(create(:user)), { question: "Hello" }) }.not_to have_enqueued_job(Agent::AnswerJob)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "an opinion on an answer" do
    let(:conversation) { conversation_of }
    let(:answer) { conversation.messages.create!(role: "assistant", content: "42") }

    def rate(body, message = answer, conv = conversation) = api_post("/api/v1/agent/conversations/#{conv.id}/messages/#{message.id}/feedback", token, body)

    it "records useful, or not useful with a category and a comment; one opinion per person, the last one counts" do
      rate({ rating: "useful" })
      expect(response).to have_http_status(:created)
      expect(violations([ "paths", "/agent/conversations/{id}/messages/{message_id}/feedback", "post" ], "201")).to eq([])

      rate({ rating: "not_useful", category: "wrong_figure", comment: "Off by ten" })

      expect(Agent::Feedback.where(message: answer)).to contain_exactly(have_attributes(user: owner, rating: "not_useful", category: "wrong_figure", comment: "Off by ten"))
    end

    it "refuses a rating or a category it does not know" do
      rate({ rating: "meh" })
      expect(response).to have_http_status(:unprocessable_content)
      rate({ rating: "not_useful", category: "nonsense" })
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "does not take an opinion on an answer of someone else's conversation" do
      other = conversation_of(create(:user))
      theirs = other.messages.create!(role: "assistant", content: "x")

      rate({ rating: "useful" }, theirs, other)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the document" do
    it "describes the agent's endpoints, each with its scope, and breaks nothing of the published version" do
      expect(doc["paths"].keys).to include("/agent/conversations", "/agent/conversations/{id}", "/agent/conversations/{id}/stop", "/agent/conversations/{id}/messages", "/agent/conversations/{id}/messages/{message_id}/feedback")
      expect(doc["paths"].select { |path, _| path.start_with?("/agent") }.values.flat_map(&:values).map { |operation| operation["x-required-scope"] }.uniq).to eq([ "agent:use" ])
      published = JSON.parse(Rails.root.join("docs/api/openapi-v1.json").read)
      expect(Api::V1::OpenApi::Compatibility.breaking_changes(published, doc)).to eq([])
    end
  end
end
