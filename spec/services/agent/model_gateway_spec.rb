require "rails_helper"

RSpec.describe Agent::ModelGateway do
  let(:stream) { instance_double("Stream", text: %w[Hel lo].each, accumulated_message: message) }
  let(:message) do
    Struct.new(:stop_reason, :content, :usage, :model).new(:end_turn, [ Struct.new(:to_h).new({ type: :text, text: "Hello" }) ], Struct.new(:input_tokens, :output_tokens).new(12, 3), "claude-x")
  end
  let(:client) { instance_double("Anthropic::Client", messages: instance_double("Messages")) }

  around do |example|
    previous = ENV.delete("AGENT_ALLOW_LIVE_PROVIDER")
    example.run
  ensure
    previous ? ENV["AGENT_ALLOW_LIVE_PROVIDER"] = previous : ENV.delete("AGENT_ALLOW_LIVE_PROVIDER")
  end

  it "does not reach the provider from a development machine or a test" do
    expect { described_class.new(client: client).call(system: "s", messages: [], tools: []) }.to raise_error(Agent::LiveProviderRefused)
  end

  context "when the provider may be reached" do
    before { ENV["AGENT_ALLOW_LIVE_PROVIDER"] = "1" }

    it "asks the configured model for the task and streams the text" do
      allow(client.messages).to receive(:stream).and_return(stream)
      pieces = []

      response = described_class.new(client: client).call(system: "Be exact.", messages: [ { role: "user", content: "Hi" } ], tools: [ { name: "t" } ], task: :light) { |piece| pieces << piece }

      expect(client.messages).to have_received(:stream).with(hash_including(model: Agent::Config.model_for(:light), system_: "Be exact.", messages: [ { role: "user", content: "Hi" } ], tools: [ { name: "t" } ]))
      expect(pieces).to eq(%w[Hel lo])
      expect(response).to have_attributes(stop_reason: "end_turn", content: [ { type: :text, text: "Hello" } ], usage: { input_tokens: 12, output_tokens: 3 }, model: "claude-x")
    end

    it "sends the provider what the redactor left, never the original: the payload that really goes is inspected" do
      allow(client.messages).to receive(:stream).and_return(stream)
      redactor = instance_double(Agent::Redactor, redact: Agent::Redactor::Result.new(system: "masked system", messages: [ { role: "user", content: "IBAN …7034" } ], stats: { "bank_identifier" => { "masked" => 1 } }))

      response = described_class.new(client: client).call(system: "system BE68539007547034", messages: [ { role: "user", content: "BE68539007547034" } ], tools: [], redactor: redactor)

      expect(client.messages).to have_received(:stream).with(hash_including(system_: "masked system", messages: [ { role: "user", content: "IBAN …7034" } ]))
      expect(response.redaction).to eq("bank_identifier" => { "masked" => 1 })
      expect(response.sent).to eq(system: "masked system", messages: [ { role: "user", content: "IBAN …7034" } ])
    end

    it "leaves the tools out when there are none, since the API refuses an empty list" do
      allow(client.messages).to receive(:stream).and_return(stream)

      described_class.new(client: client).call(system: "s", messages: [], tools: [])

      expect(client.messages).to have_received(:stream).with(satisfy { |args| !args.key?(:tools) })
    end
  end
end
