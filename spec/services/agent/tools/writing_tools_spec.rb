require "rails_helper"

# A11: what a text is written from, and the drafting tool.
RSpec.describe "The writing tools of the agent" do
  include_context "with open customer lines"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: as_of) }
  let(:registry) { Agent::ToolRegistry.new([ Agent::Tools::GetWritingContext, Agent::Tools::ProposeText, Agent::Tools::GetTextDraft ]) }

  describe Agent::Tools::GetWritingContext do
    let(:tool) { described_class }
    let(:valid_args) { { "partner_id" => alice.id } }

    before { open_line(partner: alice, amount: 100, days_overdue: 30) }

    it_behaves_like "an agent tool", permission: "agent.propose"

    it "gives the lines a reminder would ask for, with the invoice, the due date, the amount and where it comes from" do
      dunning = registry.execute("get_writing_context", valid_args, context)["data"].first["dunning"]

      expect(dunning["eligible"].first).to include("amount" => "100.00", "days_late" => 30, "reminders_sent" => 0, "ref" => a_string_starting_with("entry:"))
      expect(dunning).to include("level" => 1, "total_overdue" => "100.00", "may_add_interest" => false, "may_add_indemnity" => false)
      expect(dunning["standard_text"]).to include("Madame, Monsieur")
    end

    it "gives the lines it leaves out and why, and says there is nothing to remind when all are out" do
      Accounting::JournalEntryLine.where(partner_id: alice.id).update_all(disputed: true)

      result = registry.execute("get_writing_context", valid_args, context)

      expect(result["data"].first["dunning"]["excluded"].first).to include("reason" => "in dispute")
      expect(result["data"].first["dunning"]["blocked"]).to include("in dispute")
      expect(result["warnings"].join).to include("gets no reminder")
    end

    it "gives the company profile, or says there is none" do
      expect(registry.execute("get_writing_context", {}, context)["data"].first["profile"]).to include("note" => a_string_including("No profile"))

      Agent::Setting.for_current_entity.update!(writing_profile: { "formality" => "vous", "closing" => "With our best regards" })
      expect(registry.execute("get_writing_context", {}, context)["data"].first["profile"]).to include("formality" => "vous")
    end

    it "gives the reminder policy: interest and indemnity only when the company turned them on" do
      policy.update!(interest_enabled: true, interest_rate: 8, indemnity_enabled: true, indemnity_amount: 40)

      dunning = registry.execute("get_writing_context", valid_args, context)["data"].first["dunning"]

      expect(dunning).to include("may_add_interest" => true, "interest_rate_percent" => "8.0", "may_add_indemnity" => true, "indemnity_amount" => "40.00")
    end

    it "says the language of the partner is not known when it is not one the application writes" do
      alice.update_columns(language: "de")

      expect(registry.execute("get_writing_context", valid_args, context)["warnings"].join).to include("language of the partner is not known")
    end

    it "leaves the reminders out for a person who may not prepare them" do
      reader = create(:user)
      create(:user_entity, :manager, user: reader, entity: entity)

      expect(registry.execute("get_writing_context", valid_args, Agent::Context.build(user: reader, entity: entity, locale: :en))).to eq(Agent::ToolRegistry::FORBIDDEN)
    end
  end

  describe Agent::Tools::ProposeText do
    let(:args) { { "kind" => "rewrite", "language" => "en", "body" => "Please send the contract by Friday." } }

    it "gives the draft and says it is not sent, whatever the kind" do
      result = registry.execute("propose_text", args, context)

      expect(result["data"].first["proposal"]).to include("kind" => "text", "text_kind" => "rewrite", "body" => "Please send the contract by Friday.")
      expect(result["data"].first["next"]).to include("not sent", "cannot send")
    end

    it "gives what to correct when the server refuses, and nothing else" do
      result = registry.execute("propose_text", args.merge("body" => " "), context)

      expect(result).to include("error" => "invalid_proposal")
      expect(result["message"]).to include("body is required")
    end

    it "writes nothing: no draft, no reminder, no e-mail" do
      expect { registry.execute("propose_text", args, context) }.not_to change { [ Agent::TextDraft.count, Accounting::DunningItem.count, ActionMailer::Base.deliveries.size ] }
    end

    it "turns away a user or an entity, and a person who may not propose" do
      expect(registry.execute("propose_text", args.merge("user_id" => 1), context)).to include("error" => "invalid_arguments")
      reader = create(:user)
      create(:user_entity, :manager, user: reader, entity: entity)
      expect(registry.execute("propose_text", args, Agent::Context.build(user: reader, entity: entity, locale: :en))).to eq(Agent::ToolRegistry::FORBIDDEN)
    end
  end

  describe Agent::Tools::GetTextDraft do
    it "gives a draft of the person to revise, and never one of someone else" do
      mine = Agent::TextDraft.create!(user: user, kind: "rewrite", language: "en", payload: { "versions" => [ { "subject" => "S", "body" => "My text", "by" => "assistant" } ] }.to_json)
      theirs = Agent::TextDraft.create!(user: create(:user), kind: "rewrite", language: "en", payload: { "versions" => [] }.to_json)

      expect(registry.execute("get_text_draft", { "draft_id" => mine.id }, context)["data"].first).to include("body" => "My text", "status" => "draft")
      expect(registry.execute("get_text_draft", { "draft_id" => theirs.id }, context)).to include("error" => "not_found")
    end
  end
end
