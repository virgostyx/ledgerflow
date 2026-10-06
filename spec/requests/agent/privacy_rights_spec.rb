require "rails_helper"

# A04: a person exports and deletes their own conversations; an owner finds a natural person in the conversations of the entity, to export what concerns them or to erase it,
# with a reason and a trace that does not hold the name.
RSpec.describe "Access and erasure (A04)", type: :request do
  include_context "with_open_fiscal_year"

  let(:owner)      { create(:user) }
  let(:accountant) { create(:user) }
  let(:colleague)  { create(:user) }
  let!(:owner_membership) { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:colleague_membership) { create(:user_entity, :accountant, user: colleague, entity: entity) }

  before { enable_agent! }

  def conversation_of(user, question, answer: nil, title: "t")
    Agent::Conversation.create!(user: user, title: title).tap do |conversation|
      conversation.messages.create!(role: "user", content: question)
      conversation.messages.create!(role: "assistant", content: answer) if answer
    end
  end

  describe "a person's own conversations" do
    before { sign_in accountant }

    it "exports them as a file: the content, the names as the person read them, nobody else's" do
      mine = conversation_of(accountant, "What does Alice Dupont owe?", answer: "PERSONNE_001 owes 10.00 EUR", title: "Aged")
      mine.pseudonym_table.token_for("Alice Dupont", "person")
      conversation_of(colleague, "Secret of the colleague")

      get export_agent_conversations_path

      expect(response.media_type).to eq("application/json")
      expect(response.headers["Content-Disposition"]).to include("attachment", "agent-conversations")
      body = JSON.parse(response.body)
      expect(body["conversations"].size).to eq(1)
      expect(body["conversations"].first).to include("title" => "Aged")
      expect(body["conversations"].first["messages"].map { |m| m["content"] }).to eq([ "What does Alice Dupont owe?", "Alice Dupont owes 10.00 EUR" ])
      expect(response.body).not_to include("Secret of the colleague")
    end

    it "is not offered once the assistant is off" do
      Agent::Setting.for_current_entity.update!(enabled: false)

      get export_agent_conversations_path

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the owner's search for a natural person" do
    let!(:typed)    { conversation_of(accountant, "Did Alice Dupont pay?", answer: "PERSONNE_001 paid.", title: "Typed") }
    let!(:answered) { conversation_of(colleague, "Who owes me the most?", answer: "PERSONNE_001 owes the most.", title: "Answered") }
    let!(:unrelated) { conversation_of(colleague, "What is the VAT due?", answer: "10.00 EUR", title: "Unrelated") }

    before do
      answered.pseudonym_table.token_for("Alice Dupont", "person") # the name was masked for the model: only the pseudonym table knows it
      sign_in owner
    end

    it "finds the conversations that concern the person, whether they typed the name or only the model's answer carried it" do
      post agent_subject_requests_path, params: { name: "alice dupont", operation: "search" }

      expect(response.body).to include("Typed", "Answered")
      expect(response.body).not_to include("Unrelated")
    end

    it "tells who was talking and when, but not what was said" do
      post agent_subject_requests_path, params: { name: "Alice Dupont", operation: "search" }

      expect(response.body).to include(accountant.email, colleague.email)
      expect(response.body).not_to include("Did Alice Dupont pay?", "owes the most")
    end

    it "says when there is nothing about the person" do
      post agent_subject_requests_path, params: { name: "Zoé Inconnue", operation: "search" }

      expect(response.body).to include("No conversation mentions")
    end

    it "exports what concerns the person, with the reason written in the audit trail without the name" do
      post agent_subject_requests_path, params: { name: "Alice Dupont", operation: "export", reason: "Access request of 2026-10-06" }

      body = JSON.parse(response.body)
      expect(body["conversations"].map { |c| c["title"] }).to contain_exactly("Typed", "Answered")
      expect(response.body).to include("Did Alice Dupont pay?", "Alice Dupont owes the most")
      log = Accounting::AuditLog.where(action: "agent_subject_request").last
      expect(log).to have_attributes(user_id: owner.id, reason: "Access request of 2026-10-06")
      expect(log.payload).to include("operation" => "export", "conversations" => 2)
      expect(log.payload.to_s).not_to include("Alice", "Dupont")
    end

    it "erases what concerns the person, and only that, with the same trace" do
      expect { post agent_subject_requests_path, params: { name: "Alice Dupont", operation: "erase", reason: "Erasure request" } }.to change(Agent::Conversation, :count).by(-2)

      expect(Agent::Conversation.pluck(:title)).to eq([ "Unrelated" ])
      expect(Accounting::AuditLog.where(action: "agent_subject_request").last.payload).to include("operation" => "erase", "conversations" => 2)
    end

    it "asks for a reason before it exports or erases" do
      expect { post agent_subject_requests_path, params: { name: "Alice Dupont", operation: "erase" } }.not_to change(Agent::Conversation, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("reason")
    end

    it "does not reach the conversations of another entity" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { conversation_of(create(:user), "Did Alice Dupont pay elsewhere?", title: "Elsewhere") }

      post agent_subject_requests_path, params: { name: "Alice Dupont", operation: "erase", reason: "x" }

      expect(ActsAsTenant.without_tenant { Agent::Conversation.where(id: foreign.id) }).to exist
    end

    it "is the owner's alone" do
      sign_in accountant

      post agent_subject_requests_path, params: { name: "Alice Dupont", operation: "erase", reason: "x" }

      expect(Agent::Conversation.count).to eq(3)
    end

    it "is reachable from the assistant settings" do
      get agent_setting_path

      expect(response.body).to include(new_agent_subject_request_path)
    end
  end
end
