require "rails_helper"

# A11: what the runner does with a drafted text: a draft stored for the person, never sent; only the figures, dates and numbers that the tools gave; no token of the masking left.
RSpec.describe "Drafting a text in an answer (A11)" do
  include_context "with open customer lines"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: as_of) }
  let(:conversation) { Agent::Conversation.create!(user: user, title: "t") }
  let(:registry) { Agent::ToolRegistry.default }
  let(:due) { (as_of - 30).iso8601 }

  def text(string) = Agent::Response.new(stop_reason: "end_turn", content: [ { type: "text", text: string } ], usage: {}, model: "m")
  def call(name, input, id = "c1") = Agent::Response.new(stop_reason: "tool_use", usage: {}, model: "m", content: [ { type: "tool_use", id: id, name: name, input: input } ])

  def draft_args(body, **extra) = { "kind" => "dunning_letter", "language" => "en", "subject" => "Payment reminder", "partner_id" => alice.id, "level" => 1, "body" => body }.merge(extra)

  def play(script, question = "Write the reminder for Alice.")
    @gateway = Agent::FakeGateway.new(script)
    Agent::Runner.new(conversation: conversation, context: context, gateway: @gateway, registry: registry).ask(question)
  end

  before do
    enable_agent!
    open_line(partner: alice, amount: 100, days_overdue: 30)
  end

  it "keeps the draft for the person, with its facts, and sends nothing" do
    answer = nil
    expect do
      answer = play([ call("get_writing_context", { "partner_id" => alice.id }), call("propose_text", draft_args("Dear Alice, the invoice of 100.00 EUR is overdue since #{due}. Kind regards.", "facts" => [ { "label" => "Total", "value" => "100.00", "ref" => "partner:#{alice.id}" } ])), text("I prepared a draft for you to read.") ])
    end.not_to change { [ ActionMailer::Base.deliveries.size, Accounting::DunningItem.count ] }

    draft = answer.reload.text_drafts.first
    expect(draft).to have_attributes(kind: "dunning_letter", language: "en", level: 1, partner_id: alice.id, status: "draft", user_id: user.id, conversation_id: conversation.id)
    expect(draft.body).to eq("Dear Alice, the invoice of 100.00 EUR is overdue since #{due}. Kind regards.")
    expect(draft.facts).to eq([ { "label" => "Total", "value" => "100.00", "ref" => "partner:#{alice.id}" } ])
    expect(Accounting::AuditLog.where(action: "agent_text_draft", auditable_id: draft.id)).to exist
  end

  it "replaces an amount, a date and an invoice number that no tool gave with a placeholder, and says so" do
    body = "Dear Alice, invoice FAC2026/9999 of 999.99 EUR was due on 2026-01-01. The one of 100.00 EUR was due #{due}. Kind regards."

    play([ call("get_writing_context", { "partner_id" => alice.id }), call("propose_text", draft_args(body)), text("Done.") ])

    draft = Agent::TextDraft.last
    expect(draft.body).to eq("Dear Alice, invoice [To complete: invoice number] of [To complete: amount] EUR was due on [To complete: date]. The one of 100.00 EUR was due #{due}. Kind regards.")
    expect(draft.warnings.join).to include("3 figure(s), date(s) or invoice number(s) that no tool gave")
  end

  it "keeps a date, an amount and an invoice number that the person typed in the question, however the date is written" do
    answer = play([ call("propose_text", { "kind" => "rewrite", "language" => "en", "body" => "Please send invoice AB2026/0042 of 250.00 EUR dated 2026-02-03." }), text("Done.") ], "Rewrite: please send invoice AB2026/0042 of 250.00 EUR dated 3 February 2026.")

    expect(answer.reload.text_drafts.first.body).to eq("Please send invoice AB2026/0042 of 250.00 EUR dated 2026-02-03.")
  end

  it "turns the tokens of the masking into the names they stand for, and sends the draft back if a token stands for nobody" do
    token = conversation.pseudonym_table.token_for("Alice Janssens", "person")

    play([ call("propose_text", { "kind" => "rewrite", "language" => "en", "body" => "Dear #{token}, thank you." }), text("Done.") ])
    expect(Agent::TextDraft.last.body).to eq("Dear Alice Janssens, thank you.")

    answer = play([ call("propose_text", { "kind" => "rewrite", "language" => "en", "body" => "Dear PERSONNE_099, thank you." }, "c2"), text("I could not write it.") ])
    expect(@gateway.requests.last[:messages].last[:content].first[:content]).to include("tokens that stand for nobody")
    expect(answer.reload.text_drafts.count).to eq(0)
    expect(Agent::SecurityEvent.where(kind: "invented_token")).to exist
  end

  it "does not draft a reminder for a customer whose line is in dispute, and lets the model explain" do
    Accounting::JournalEntryLine.where(partner_id: alice.id).update_all(disputed: true)

    answer = play([ call("propose_text", draft_args("Dear Alice, please pay.")), text("This customer is in dispute: no reminder is written.") ])

    expect(@gateway.requests.last[:messages].last[:content].first[:content]).to include("Refused", "in dispute")
    expect(answer.reload.text_drafts).to be_empty
  end

  it "adds a version to the draft the person asked to revise, and keeps the first one" do
    first = Agent::TextDraft.create!(user: user, kind: "rewrite", language: "en", payload: { "versions" => [ { "subject" => nil, "body" => "Send it soon.", "by" => "assistant", "at" => Time.current.iso8601 } ] }.to_json)

    play([ call("get_text_draft", { "draft_id" => first.id }), call("propose_text", { "kind" => "rewrite", "language" => "en", "body" => "Please send it today.", "revises" => first.id }, "c2"), text("Revised.") ])

    expect(first.reload.versions.map { |version| version["body"] }).to eq([ "Send it soon.", "Please send it today." ])
    expect(Agent::TextDraft.count).to eq(1)
  end

  it "keeps no draft when the answer is stopped" do
    runner = Agent::Runner.new(conversation: conversation, context: context, gateway: Agent::FakeGateway.new([ call("propose_text", { "kind" => "rewrite", "language" => "en", "body" => "x" }), text("y") ]), registry: registry)

    runner.ask("Q", stop: -> { true })

    expect(Agent::TextDraft.count).to eq(0)
  end
end
