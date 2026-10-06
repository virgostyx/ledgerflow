require "rails_helper"

# A03: two entities, two people, two conversations at the same moment in the same process: each reads its own books and nothing else, round after round.
RSpec.describe "The agent under concurrency", :concurrency do
  include_context "with_open_fiscal_year"

  let(:entity_b) { create(:entity, name: "Entity B") }
  let(:user_a) { create(:user) }
  let(:user_b) { create(:user) }

  def prepare(entity_record, user, partner_name)
    ActsAsTenant.with_tenant(entity_record) do
      entity_record.update!(features: entity_record.features.merge("agent" => true))
      Agent::Setting.for_current_entity.update!(enabled: true)
      accept_agent_consent!(entity_record)
      create(:user_entity, :accountant, user: user, entity: entity_record)
      create(:partner, name: partner_name, city: "Sharedcity", is_natural_person: false) # a company: its name is not masked, so the test can see whose it is
    end
  end

  def ask_in(entity_record, user)
    lambda do
      ActsAsTenant.with_tenant(entity_record) do
        conversation = Agent::Conversation.create!(user: user, title: "t")
        script = [ Agent::Response.new(stop_reason: "tool_use", usage: {}, model: "m", content: [ { type: "tool_use", id: "1", name: "search_partners", input: { "q" => "Sharedcity" } },
                                                                                                    { type: "tool_use", id: "2", name: "get_company_context", input: {} } ]),
                   Agent::Response.new(stop_reason: "end_turn", usage: {}, model: "m", content: [ { type: "text", text: "ok" } ]) ]
        gateway = Agent::FakeGateway.new(script)
        Agent::Runner.new(conversation: conversation, context: Agent::Context.build(user: user, entity: entity_record, locale: :en), gateway: gateway).ask("Who is there?")
        gateway.requests.last[:messages].last[:content].map { |block| block[:content] }.join(" ")
      end
    end
  end

  it "keeps each entity to its own partners and its own name, in every round" do
    prepare(entity, user_a, "Partner of A")
    prepare(entity_b, user_b, "Partner of B")

    10.times do
      seen_a, seen_b = concurrently(ask_in(entity, user_a), ask_in(entity_b, user_b), entity: entity)

      expect(seen_a).to include("Partner of A", entity.name)
      expect(seen_a).not_to include("Partner of B", "Entity B")
      expect(seen_b).to include("Partner of B", "Entity B")
      expect(seen_b).not_to include("Partner of A", entity.name)
    end
  end

  it "keeps the conversations of each entity apart, whoever asks" do
    prepare(entity, user_a, "Partner of A")
    prepare(entity_b, user_b, "Partner of B")

    concurrently(ask_in(entity, user_a), ask_in(entity_b, user_b), entity: entity)

    expect(ActsAsTenant.without_tenant { Agent::Conversation.where(entity_id: entity.id).pluck(:user_id) }).to eq([ user_a.id ])
    expect(ActsAsTenant.without_tenant { Agent::Conversation.where(entity_id: entity_b.id).pluck(:user_id) }).to eq([ user_b.id ])
  end
end
