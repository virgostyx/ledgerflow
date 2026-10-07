require "rails_helper"

# A01: an owner reads someone else's conversation only by an exceptional procedure: a reason, a second factor, a trace in the audit trail, a notice to the author.
RSpec.describe "Exceptional review of a conversation (A01)", type: :request do
  include_context "with_open_fiscal_year"

  let(:owner)      { create(:user, email: "owner@firm.test") }
  let(:author)     { create(:user, email: "author@firm.test") }
  let(:accountant) { create(:user) }
  let!(:owner_membership)  { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:author_membership) { create(:user_entity, :accountant, user: author, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:conversation) do
    Agent::Conversation.create!(user: author, title: "Does Alice Dupont owe anything?").tap do |c|
      c.pseudonym_table.token_for("Alice Dupont", "person")
      c.messages.create!(role: "user", content: "Does Alice Dupont owe anything?")
      c.messages.create!(role: "assistant", content: "PERSONNE_001 owes 10.00 EUR.")
    end
  end
  let(:reason) { "Complaint about an answer, to be checked" }

  before do
    enable_agent!
    owner.update!(totp_secret: Totp.generate_secret, totp_enabled_at: Time.current)
  end

  def code(offset = 0) = Totp.code(owner.reload.totp_secret, Time.now + (offset * 30))

  def review(params = {}) = post(agent_reviews_path, params: { conversation_id: conversation.id, reason: reason, code: code }.merge(params))

  describe "the list" do
    before { sign_in owner }

    it "shows who talked, when and how much, never what was said: not even the title" do
      get agent_reviews_path

      expect(response.body).to include("author@firm.test")
      expect(response.body).not_to include("Alice", "owe anything", "10.00")
    end

    it "does not offer the owner their own conversations" do
      Agent::Conversation.create!(user: owner, title: "Mine").messages.create!(role: "user", content: "x")

      get agent_reviews_path

      expect(response.body.scan('value="Review"').size).to eq(1) # the author's conversation only
    end

    it "does not show the conversations of another entity" do
      ActsAsTenant.with_tenant(create(:entity)) { Agent::Conversation.create!(user: create(:user, email: "elsewhere@other.test"), title: "x") }

      get agent_reviews_path

      expect(response.body).not_to include("elsewhere@other.test")
    end
  end

  describe "reading one" do
    before { sign_in owner }

    it "needs a reason, a code of the second factor, and then shows the conversation read-only, with the names as the author read them" do
      expect { review }.to change(Agent::ConversationReview, :count).by(1)

      record = Agent::ConversationReview.last
      expect(response).to redirect_to(agent_review_path(record))
      expect(record).to have_attributes(conversation: conversation, author: author, reviewer: owner, reason: reason, message_count: 2)
      follow_redirect!
      expect(response.body).to include("Does Alice Dupont owe anything?", "Alice Dupont owes 10.00 EUR.", "Read-only")
      expect(response.body).not_to include("PERSONNE_001")
      expect(response.body).not_to include("Useful") # no action on someone else's answer
    end

    it "writes the reading in the audit trail, with the reason and who read it" do
      review

      log = Accounting::AuditLog.where(action: "agent_conversation_review").last
      expect(log).to have_attributes(user_id: owner.id, reason: reason, auditable_type: "Agent::ConversationReview")
      expect(log.payload.to_s).not_to include("Alice")
    end

    it "tells the author, in the application and by e-mail, who read it, when and why" do
      expect { review }.to have_enqueued_mail(Agent::ReviewMailer, :conversation_read)

      notification = Accounting::Notification.where(user: author, event: "agent_conversation_read").last
      expect(notification).to be_present
      expect(notification.data).to include("by" => "owner@firm.test", "reason" => reason)
    end

    it "shows the author, in the panel, that the conversation was read" do
      review
      sign_in author

      get agent_conversation_path(conversation)

      expect(response.body).to include("owner@firm.test", "read this conversation", reason)
    end

    it "refuses a reason that says nothing" do
      expect { review(reason: "ok") }.not_to change(Agent::ConversationReview, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("reason")
    end

    it "refuses a wrong code, a code used before, and an owner with no second factor" do
      expect { review(code: "000000") }.not_to change(Agent::ConversationReview, :count)
      expect(response.body).to include("code")

      review
      expect { review(code: code(0)) }.not_to change(Agent::ConversationReview, :count) # the same step: a code is not used twice
      expect { review(code: code(1)) }.to change(Agent::ConversationReview, :count).by(1)

      owner.update!(totp_enabled_at: nil)
      expect { review(code: code(2)) }.not_to change(Agent::ConversationReview, :count)
      expect(response.body).to include("authenticator")
    end

    it "does not let an owner read their own conversation through it, since they can read it" do
      mine = Agent::Conversation.create!(user: owner, title: "mine")

      expect { review(conversation_id: mine.id) }.not_to change(Agent::ConversationReview, :count)
    end

    it "does not find a conversation of another entity" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { Agent::Conversation.create!(user: create(:user), title: "x") }

      expect { review(conversation_id: foreign.id) }.not_to change(Agent::ConversationReview, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "who may" do
    it "is the owner's alone: an accountant reads nothing" do
      sign_in accountant

      expect { review }.not_to change(Agent::ConversationReview, :count)
      expect(Accounting::AuditLog.where(action: "agent_conversation_review")).to be_empty
    end

    it "gives the reading to the owner who made the request only, and for a short while" do
      sign_in owner
      review
      record = Agent::ConversationReview.last
      other_owner = create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) }

      sign_in other_owner
      get agent_review_path(record)
      expect(response).to redirect_to(agent_reviews_path)

      sign_in owner
      record.update_columns(reviewed_at: 31.minutes.ago)
      get agent_review_path(record)
      expect(response).to redirect_to(agent_reviews_path)
    end

    it "is closed while the assistant feature is off" do
      entity.update!(features: entity.features.merge("agent" => false))
      sign_in owner

      get agent_reviews_path

      expect(response).to redirect_to(accounting_root_path)
    end

    it "is reachable from the assistant settings" do
      sign_in owner

      get agent_setting_path

      expect(response.body).to include(agent_reviews_path)
    end
  end

  it "keeps the record of a reading after the conversation is deleted, without the conversation" do
    sign_in owner
    review
    record = Agent::ConversationReview.last

    conversation.destroy!

    expect(record.reload).to have_attributes(conversation_id: nil, author: author, reviewer: owner, message_count: 2)
  end
end
