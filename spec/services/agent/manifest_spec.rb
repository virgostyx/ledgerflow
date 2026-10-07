require "rails_helper"

# A12: the version of the agent, as a hash of what makes it behave: its instructions, its tools, its models, its masking. Each answer carries it, so that an answer can be put back in
# the version that gave it, and two versions can be told apart.
RSpec.describe Agent::Manifest do
  subject!(:manifest) { described_class.current } # taken before an example changes anything

  it "hashes each component of the agent: the instructions, the tool catalog, the models and the masking" do
    expect(manifest.components.keys).to contain_exactly("system_prompt", "tools", "models", "masking")
    expect(manifest.components.values).to all(match(/\A\h{16}\z/))
  end

  it "gives one hash for the whole, the same every time for the same agent" do
    expect(manifest.hash_value).to match(/\A\h{16}\z/)
    expect(described_class.current.hash_value).to eq(manifest.hash_value)
  end

  it "changes when the instructions change" do
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with(Agent::SystemPrompt::PRINCIPLES).and_return("different principles")

    expect(described_class.current.hash_value).not_to eq(manifest.hash_value)
    expect(described_class.current.components["system_prompt"]).not_to eq(manifest.components["system_prompt"])
    expect(described_class.current.components["tools"]).to eq(manifest.components["tools"])
  end

  it "changes when a tool's description changes, which is what steers the model's choice" do
    tool = Agent::Tools::GetLedger
    original = tool.description

    tool.description("A different description. Use it for everything.")
    begin
      expect(described_class.current.components["tools"]).not_to eq(manifest.components["tools"])
    ensure
      tool.description(original)
    end
  end

  it "changes when the model of a task changes" do
    allow(Agent::Config).to receive(:settings).and_return(Agent::Config.settings.deep_merge(models: { chat_default: "another-model" }))

    expect(described_class.current.components["models"]).not_to eq(manifest.components["models"])
  end

  it "does not change with the key, the entity or the data: only with the agent" do
    expect(manifest.components.to_s).not_to match(/sk-ant|@/)
  end

  it "is stored on every answer, to say which version gave it" do
    entity = create(:entity)
    ActsAsTenant.with_tenant(entity) do
      user = create(:user)
      create(:user_entity, :accountant, user: user, entity: entity)
      enable_agent!(entity)
      conversation = Agent::Conversation.create!(user: user, title: "t")
      script = [ Agent::Response.new(stop_reason: "end_turn", content: [ { type: "text", text: "ok" } ], usage: {}, model: "m") ]

      answer = Agent::Runner.new(conversation: conversation, context: Agent::Context.build(user: user, entity: entity, locale: :en), gateway: Agent::FakeGateway.new(script)).ask("Q")

      expect(answer.manifest_hash).to eq(manifest.hash_value)
    end
  end
end
