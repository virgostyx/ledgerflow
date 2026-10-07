require "rails_helper"

# A05: "Check" replays what an answer rested on and says whether it is still true.
RSpec.describe Agent::Verification do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: Date.current) }
  let(:conversation) { Agent::Conversation.create!(user: user, title: "t") }
  let(:sales) { create(:journal, :sale) }
  let(:customers) { account_400 }
  let(:revenue) { account_700 }
  let(:partner) { create(:partner, name: "Acme SA", is_natural_person: false) }

  def invoice(amount)
    entry = create(:journal_entry, :draft, journal: sales, fiscal_year: fiscal_year, entry_date: Date.current)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: customers, partner: partner, invoice: create(:invoice, :posted, fiscal_year: fiscal_year, due_date: Date.current + 10), debit: BigDecimal(amount), credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: revenue, debit: 0, credit: BigDecimal(amount))
    entry.post!
  end

  # An answer that rested on the aged balance of customers, as the runner records it.
  def answered
    invoice("100.00")
    script = [ Agent::Response.new(stop_reason: "tool_use", usage: {}, model: "m", content: [ { type: "tool_use", id: "1", name: "get_aged_balance", input: { "kind" => "customer" } } ]),
               Agent::Response.new(stop_reason: "end_turn", usage: {}, model: "m", content: [ { type: "text", text: "Customers owe 100.00 EUR." } ]) ]
    Agent::Runner.new(conversation: conversation, context: context, gateway: Agent::FakeGateway.new(script)).ask("What do customers owe?")
  end

  before { enable_agent! }

  it "says the answer is still valid when the books give the same figures" do
    result = described_class.call(message: answered, context: context)

    expect(result).to be_valid
    expect(result.books_moved).to be false
  end

  it "says so when the books moved but the figures asked about did not" do
    message = answered
    other = create(:partner, name: "Other SA", is_natural_person: false)
    entry = create(:journal_entry, :draft, journal: create(:journal, :misc), fiscal_year: fiscal_year, entry_date: Date.current)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: 5, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: account_440, partner: other, debit: 0, credit: 5)
    entry.post!

    result = described_class.call(message: message, context: context)

    expect(result).to be_valid
    expect(result.books_moved).to be true
  end

  it "says what changed when the figures are no longer the same: the amounts that appeared and those that went" do
    message = answered
    invoice("250.00")

    result = described_class.call(message: message, context: context)

    expect(result).not_to be_valid
    change = result.changes.first
    expect(change).to have_attributes(tool: "get_aged_balance", arguments: { "kind" => "customer" }, error: nil)
    expect(change.added).to include("350.00")
    expect(change.removed).to include("100.00")
    expect(result.books_moved).to be true
  end

  it "replays on the day of the answer, not on today's: the same question is the same question" do
    message = answered
    message.update_columns(created_at: 3.days.ago)
    seen = []
    allow_any_instance_of(Agent::ToolRegistry).to receive(:execute).and_wrap_original { |original, name, args, ctx, **kw| seen << ctx.today; original.call(name, args, ctx, **kw) }

    described_class.call(message: message, context: context)

    expect(seen).to eq([ 3.days.ago.to_date ])
  end

  it "says a call can no longer be made when the person has lost the right to it, instead of saying the figures changed" do
    message = answered
    membership.update!(custom_role: CustomRole.create!(name: "No reports", permissions: %w[agent.use records.view])) # a right taken away since the answer

    result = described_class.call(message: message, context: context)

    expect(result.changes.first).to have_attributes(tool: "get_aged_balance", error: "forbidden")
  end

  it "does not replay a call that failed, nor an answer that called nothing" do
    plain = conversation.messages.create!(role: "assistant", content: "Hello")
    failed = conversation.messages.create!(role: "assistant", content: "x")
    failed.tool_calls.create!(tool: "get_audit_trail", arguments: "{}", status: "error", error: "forbidden")

    expect(described_class.call(message: plain, context: context)).to be_valid
    expect(described_class.call(message: failed, context: context)).to be_valid
  end
end
