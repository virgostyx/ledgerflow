require "rails_helper"

# A07: propose_entry and propose_task answer with a validated proposal or with what to correct, and write nothing.
RSpec.describe "The proposal tools of the agent" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: fiscal_year.start_date + 40) }
  let(:registry) { Agent::ToolRegistry.new([ Agent::Tools::ProposeEntry, Agent::Tools::ProposeTask ]) }
  let(:journal) { create(:journal, :purchase) }
  let(:entry_args) do
    { "journal" => journal.code, "entry_date" => (fiscal_year.start_date + 5).iso8601, "description" => "Fuel", "rationale" => "Fuel of the company car.", "certainty" => "general",
      "lines" => [ { "account" => "604000", "side" => "debit", "amount" => "60.00" }, { "account" => "440000", "side" => "credit", "amount" => "60.00" } ] }
  end

  it "needs agent.propose, which the reader does not have" do
    expect(Agent::Tools::ProposeEntry.permission).to eq("agent.propose")
    expect(Agent::Tools::ProposeTask.permission).to eq("agent.propose")
    reader = create(:user)
    create(:user_entity, :manager, user: reader, entity: entity)

    expect(registry.execute("propose_entry", entry_args, Agent::Context.build(user: reader, entity: entity, locale: :en))).to eq(Agent::ToolRegistry::FORBIDDEN)
  end

  it "gives a proposal that passes in the standard envelope, saying that nothing exists yet" do
    result = registry.execute("propose_entry", entry_args, context)

    expect(result["data"].first).to include("valid" => true)
    expect(result["data"].first["proposal"]).to include("kind" => "entry_draft", "totals" => { "debit" => "60.00", "credit" => "60.00" })
    expect(result["data"].first["next"]).to include("does not exist yet")
  end

  it "gives what to correct, in a code the model knows, and never a proposal that does not pass" do
    result = registry.execute("propose_entry", entry_args.merge("lines" => [ { "account" => "604000", "side" => "debit", "amount" => "60.00" }, { "account" => "440000", "side" => "credit", "amount" => "59.00" } ]), context)

    expect(result).to include("error" => "invalid_proposal")
    expect(result["message"]).to include("not balanced")
    expect(result).not_to have_key("data")
  end

  it "turns away an entity, a company or a user in the arguments, like every tool" do
    %w[company_id entity_id user_id].each { |key| expect(registry.execute("propose_entry", entry_args.merge(key => 1), context)).to include("error" => "invalid_arguments") }
  end

  it "writes nothing: no entry, no task, no proposal" do
    expect { registry.execute("propose_entry", entry_args, context) }.not_to change { [ Accounting::JournalEntry.count, Accounting::Task.count, Agent::Proposal.count ] }
    expect { registry.execute("propose_task", { "title" => "Check", "kind" => "to_check", "rationale" => "x", "certainty" => "given" }, context) }.not_to change { [ Accounting::Task.count, Agent::Proposal.count ] }
  end

  describe "propose_task" do
    let(:partner) { create(:partner, :supplier, name: "Fournisseur", vat_number: nil) }
    let(:task_args) { { "title" => "Ask for the contract", "kind" => "missing_document", "rationale" => "No document.", "certainty" => "given", "target" => "partner:#{partner.id}", "due_on" => (context.today + 3).iso8601 } }

    it "gives a normalized task" do
      expect(registry.execute("propose_task", task_args, context)["data"].first["proposal"]).to include("kind" => "task", "title" => "Ask for the contract", "target_type" => "Accounting::Partner", "priority" => "normal")
    end

    it "refuses a target that is not a thing of the entity, a date in the past, and a kind it does not know" do
      expect(registry.execute("propose_task", task_args.merge("target" => "partner:0"), context)["message"]).to include("target must be")
      expect(registry.execute("propose_task", task_args.merge("due_on" => (context.today - 1).iso8601), context)["message"]).to include("cannot be in the past")
      expect(registry.execute("propose_task", task_args.merge("kind" => "nope"), context)).to include("error" => "invalid_arguments")
    end
  end
end
