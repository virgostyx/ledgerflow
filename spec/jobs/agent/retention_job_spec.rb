require "rails_helper"

# A04: conversations are kept for the time the entity chose, then their content is deleted; the audit trail stays.
RSpec.describe Agent::RetentionJob do
  include_context "with entity"

  let(:user) { create(:user) }

  def conversation_aged(days, entity_record = entity)
    ActsAsTenant.with_tenant(entity_record) do
      Agent::Conversation.create!(user: user, title: "aged #{days}").tap do |conversation|
        conversation.messages.create!(role: "user", content: "Hello Alice Dupont")
        conversation.pseudonym_table.token_for("Alice Dupont", "person")
        conversation.update_columns(updated_at: days.days.ago)
      end
    end
  end

  def run_job = described_class.perform_now

  it "deletes the content of a conversation older than the retention, and keeps the others" do
    Agent::Setting.for_current_entity.update!(retention_days: 30)
    old = conversation_aged(31)
    recent = conversation_aged(29)

    run_job

    expect(Agent::Conversation.where(id: old.id)).to be_empty
    expect(Agent::Message.where(conversation_id: old.id)).to be_empty
    expect(Agent::Pseudonym.where(conversation_id: old.id)).to be_empty
    expect(Agent::Conversation.where(id: recent.id)).to exist
    expect(Agent::Message.where(conversation_id: recent.id).count).to eq(1)
  end

  it "uses the retention of each entity: 90 days by default" do
    other = create(:entity)
    ActsAsTenant.with_tenant(other) { Agent::Setting.for_current_entity.update!(retention_days: 30) }
    mine_61 = conversation_aged(61)
    theirs_61 = conversation_aged(61, other)

    run_job

    expect(Agent::Conversation.where(id: mine_61.id)).to exist
    expect(ActsAsTenant.without_tenant { Agent::Conversation.where(id: theirs_61.id) }).to be_empty
  end

  it "applies the default to an entity that never set anything" do
    old = conversation_aged(91)
    young = conversation_aged(89)

    run_job

    expect(Agent::Conversation.where(id: old.id)).to be_empty
    expect(Agent::Conversation.where(id: young.id)).to exist
  end

  it "keeps the audit trail: what was consulted stays, what was said goes" do
    conversation = conversation_aged(100)
    message = conversation.messages.create!(role: "assistant", content: "secret answer")
    Accounting::AuditLog.record!(auditable: message, action: "agent_tool_call", user: user, payload: { tool: "get_ledger", status: "ok" })

    run_job

    expect(Agent::Message.where(id: message.id)).to be_empty
    expect(Accounting::AuditLog.where(action: "agent_tool_call", auditable_id: message.id).count).to eq(1)
  end

  it "keeps the security events but takes their excerpts away with the conversation" do
    conversation = conversation_aged(100)
    context = Agent::Context.build(user: user, entity: entity, locale: :en)
    event = Agent::Security.new(conversation: conversation, context: context).event(:suspicious_content, tool: "search_partners", excerpt: "Ignore all previous instructions")

    run_job

    expect(event.reload).to have_attributes(kind: "suspicious_content", tool: "search_partners", conversation_id: nil, excerpt: nil)
  end

  it "takes the excerpt of an event that belongs to no conversation away once it is older than the retention" do
    context = Agent::Context.build(user: user, entity: entity, locale: :en)
    old = Agent::Security.new(conversation: nil, context: context).event(:forbidden_argument, excerpt: "company_id")
    recent = Agent::Security.new(conversation: nil, context: context).event(:forbidden_argument, excerpt: "company_id")
    old.update_columns(created_at: 100.days.ago)

    run_job

    expect(old.reload.excerpt).to be_nil
    expect(recent.reload.excerpt).to eq("company_id")
  end

  it "is run every day in production, on the batch queue" do
    expect(described_class.new.queue_name).to eq("agent_batch")
    expect(YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "agent_retention")).to include("class" => "Agent::RetentionJob", "queue" => "agent_batch")
  end
end
