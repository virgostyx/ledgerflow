require "rails_helper"

# A01, the screens and their guards: who may open the panel, whose conversation it is, the question that starts the answer, the stop button, the opinion on an answer.
RSpec.describe "The agent's conversations (A01)", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:colleague)  { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:colleague_membership) { create(:user_entity, :accountant, user: colleague, entity: entity) }

  before do
    entity.update!(features: entity.features.merge("agent" => true))
    Agent::Setting.for_current_entity.update!(enabled: true)
    accept_agent_consent!
    sign_in accountant
  end

  def mine(**attrs) = Agent::Conversation.create!({ user: accountant, title: "Mine" }.merge(attrs))
  def theirs = Agent::Conversation.create!(user: colleague, title: "Theirs")

  around do |example|
    previous = ENV.delete("AGENT_KILL_SWITCH")
    example.run
  ensure
    previous ? ENV["AGENT_KILL_SWITCH"] = previous : ENV.delete("AGENT_KILL_SWITCH")
  end

  describe "who may use it" do
    {
      "the agent feature of the entity is off" => -> { entity.update!(features: entity.features.merge("agent" => false)) },
      "the owner has not turned it on"         => -> { Agent::Setting.for_current_entity.update!(enabled: false) },
      "the emergency switch is on"             => -> { ENV["AGENT_KILL_SWITCH"] = "1" }
    }.each do |reason, break_it|
      it "is closed when #{reason}" do
        instance_exec(&break_it)

        get agent_conversations_path
        expect(response).to have_http_status(:forbidden)

        post agent_conversations_path
        expect(response).to have_http_status(:forbidden)
        expect(Agent::Conversation.count).to eq(0)
      end
    end

    it "refuses the next message of a person whose right was taken away, in a conversation already open" do
      conversation = mine
      membership.update!(role: :auditor, valid_until: 1.month.from_now)

      expect { post agent_conversation_messages_path(conversation), params: { question: "Hello" } }.not_to have_enqueued_job(Agent::AnswerJob)
      expect(response).to have_http_status(:forbidden)
    end

    it "is closed to someone not signed in" do
      sign_out accountant

      get agent_conversations_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "the panel on every page" do
    it "is offered where the agent can be used, with its tab, its drawer and a keyboard shortcut" do
      get accounting_root_path

      expect(response.body).to include('id="agent_drawer"', 'aria-keyshortcuts="Control+/"', 'role="complementary"')
    end

    it "is nowhere to be seen once the agent is off for the entity, or the emergency switch is on" do
      Agent::Setting.for_current_entity.update!(enabled: false)
      get accounting_root_path
      expect(response.body).not_to include("agent_drawer")

      Agent::Setting.for_current_entity.update!(enabled: true)
      ENV["AGENT_KILL_SWITCH"] = "1"
      get accounting_root_path
      expect(response.body).not_to include("agent_drawer")
    end

    it "is not offered to a person without the right" do
      membership.update!(role: :auditor, valid_until: 1.month.from_now)

      get accounting_root_path

      expect(response.body).not_to include("agent_drawer")
    end
  end

  describe "whose conversation it is" do
    it "lists mine only, archived ones apart" do
      mine(title: "Aged balance"); mine(title: "Old one").archive!; theirs

      get agent_conversations_path

      expect(response.body).to include("Aged balance")
      expect(response.body).not_to include("Theirs", "Old one")
    end

    it "does not show, rename, stop or delete someone else's, an owner of the entity included" do
      other = theirs
      owner = create(:user_entity, :admin, user: create(:user), entity: entity).user
      sign_out accountant

      # an unknown record ends the request with an exception that drops the session of the test client, so the owner signs in again before each request
      [ -> { get agent_conversation_path(other) },
        -> { patch agent_conversation_path(other), params: { agent_conversation: { title: "Mine now" } } },
        -> { post agent_conversation_stop_path(other) },
        -> { delete agent_conversation_path(other) } ].each do |request|
        sign_in owner
        request.call
        expect(response).to have_http_status(:not_found)
      end
      expect(other.reload).to have_attributes(title: "Theirs", stop_requested_at: nil)
    end

    it "does not show a conversation of another entity" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { Agent::Conversation.create!(user: accountant, title: "Elsewhere") }

      get agent_conversation_path(foreign)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "opening one" do
    it "opens a conversation on the entity at hand, from the screen and the object it was asked on" do
      post agent_conversations_path, params: { screen: "reports/aged_balance", subject_type: "R04", subject_id: "p-1042" }

      conversation = Agent::Conversation.last
      expect(conversation).to have_attributes(user: accountant, entity: entity, origin_screen: "reports/aged_balance", context_ref: { "type" => "R04", "id" => "p-1042" })
      expect(response).to redirect_to(agent_conversation_path(conversation))
    end

    it "keeps a reference that is not shaped like one out of the conversation" do
      post agent_conversations_path, params: { subject_type: "<script>", subject_id: "x" * 200 }

      expect(Agent::Conversation.last.context_ref).to eq({})
    end

    it "shows the panel, with examples to start from when it is empty and what the agent knows" do
      get agent_conversation_path(mine(context_ref: { "type" => "R04", "id" => "p-1" }))

      expect(response.body).to include("Ask a question", "What the agent knows", "R04")
    end

    it "shows the tokens of an answer as the names they stand for, to the person who asked" do
      conversation = mine
      conversation.pseudonym_table.token_for("Alice Dupont", "person")
      conversation.messages.create!(role: "assistant", content: "PERSONNE_001 owes **10.00 EUR**; PERSONNE_099 is unknown.")

      get agent_conversation_path(conversation)

      expect(response.body).to include("Alice Dupont owes", "PERSONNE_099 is unknown")
      expect(response.body).not_to include("PERSONNE_001")
    end

    it "shows the answers as safe HTML: nothing the model wrote runs" do
      conversation = mine
      conversation.messages.create!(role: "assistant", content: "Total **12,00 EUR** <script>alert(1)</script> ![x](http://evil.example/p.png)")

      get agent_conversation_path(conversation)

      expect(response.body).to include("<strong>12,00 EUR</strong>")
      expect(response.body).not_to include("<script>alert", "evil.example")
    end
  end

  describe "the badges of an answer" do
    it "tells discreetly that data looked like an instruction, or that something was taken out of the answer" do
      conversation = mine
      conversation.messages.create!(role: "assistant", content: "Done.", flags: %w[suspicious_content content_removed])
      conversation.messages.create!(role: "assistant", content: "Plain.")

      get agent_conversation_path(conversation)

      expect(response.body.scan("looks like an instruction").size).to eq(1)
      expect(response.body.scan("was removed from this answer").size).to eq(1)
    end
  end

  describe "a question" do
    it "starts the answer in the background and shows the question and the live bubble" do
      conversation = mine

      expect { post agent_conversation_messages_path(conversation), params: { question: "Who owes me the most?" }, as: :turbo_stream }
        .to have_enqueued_job(Agent::AnswerJob).with(conversation, "Who owes me the most?", "en")

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("Who owes me the most?", "agent_conversation_#{conversation.id}_live")
    end

    it "titles an untitled conversation from its first question" do
      conversation = mine(title: nil)

      post agent_conversation_messages_path(conversation), params: { question: "Who owes me the most this month, and since when?" }, as: :turbo_stream

      expect(conversation.reload.title).to start_with("Who owes me the most")
    end

    it "refuses an empty or very long question, with a message that says why, and sends nothing" do
      conversation = mine

      expect do
        post agent_conversation_messages_path(conversation), params: { question: "  " }, as: :turbo_stream
        expect(response).to have_http_status(:unprocessable_entity)
        post agent_conversation_messages_path(conversation), params: { question: "x" * 4001 }, as: :turbo_stream
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("4000")
      end.not_to have_enqueued_job(Agent::AnswerJob)
    end

    it "refuses a question over the limit, says which limit, and sends nothing" do
      conversation = mine
      stub_const("Agent::Config", Agent::Config.dup) # keep the real configuration for the other examples
      allow(Agent::Config).to receive(:quotas).and_return({ per_hour: 1, per_day: 100, concurrent_per_entity: 3 })
      conversation.messages.create!(role: "user", content: "earlier")

      expect { post agent_conversation_messages_path(conversation), params: { question: "One too many" }, as: :turbo_stream }.not_to have_enqueued_job(Agent::AnswerJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("1 questions per hour")
    end

    it "marks the conversation as being answered until the answer is over" do
      conversation = mine

      post agent_conversation_messages_path(conversation), params: { question: "Hello" }, as: :turbo_stream

      expect(conversation.reload.answering_since).to be_present
    end

    it "does not answer a conversation that is archived" do
      conversation = mine.tap(&:archive!)

      expect { post agent_conversation_messages_path(conversation), params: { question: "Hello" }, as: :turbo_stream }.not_to have_enqueued_job(Agent::AnswerJob)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "the buttons" do
    it "stops: the request is written, nothing else happens" do
      conversation = mine

      post agent_conversation_stop_path(conversation)

      expect(response).to have_http_status(:no_content)
      expect(conversation.reload.stop_requested_at).to be_present
    end

    it "renames and archives" do
      conversation = mine

      patch agent_conversation_path(conversation), params: { agent_conversation: { title: "Renamed" } }
      expect(conversation.reload.title).to eq("Renamed")
      patch agent_conversation_path(conversation), params: { agent_conversation: { archived: "1" } }
      expect(conversation.reload).to be_archived
    end

    it "deletes the conversation and what was said in it" do
      conversation = mine
      conversation.messages.create!(role: "user", content: "Hello")

      expect { delete agent_conversation_path(conversation) }.to change(Agent::Conversation, :count).by(-1).and change(Agent::Message, :count).by(-1)
    end
  end

  describe "an opinion on an answer" do
    let(:conversation) { mine }
    let(:answer) { conversation.messages.create!(role: "assistant", content: "42") }

    it "records useful, and then not useful with a category and a comment: one opinion per person" do
      post agent_conversation_message_feedback_path(conversation, answer), params: { rating: "useful" }
      expect(Agent::Feedback.where(message: answer).pluck(:rating)).to eq([ "useful" ])

      post agent_conversation_message_feedback_path(conversation, answer), params: { rating: "not_useful", category: "wrong_figure", comment: "Off by ten" }

      expect(Agent::Feedback.where(message: answer)).to contain_exactly(have_attributes(user: accountant, rating: "not_useful", category: "wrong_figure", comment: "Off by ten"))
    end

    it "does not take an opinion on the answer of someone else's conversation" do
      other = theirs.messages.create!(role: "assistant", content: "x")

      post agent_conversation_message_feedback_path(other.conversation, other), params: { rating: "useful" }

      expect(response).to have_http_status(:not_found)
      expect(Agent::Feedback.count).to eq(0)
    end

    it "refuses a category that does not exist" do
      post agent_conversation_message_feedback_path(conversation, answer), params: { rating: "not_useful", category: "nonsense" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
