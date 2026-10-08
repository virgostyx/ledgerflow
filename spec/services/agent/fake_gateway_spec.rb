require "rails_helper"

RSpec.describe Agent::FakeGateway do
  it "replays what it was given, in order, and remembers what it was asked" do
    gateway = described_class.new([ Agent::Response.new(stop_reason: "end_turn", content: [ { type: "text", text: "one" } ], usage: {}, model: "m") ])

    response = gateway.call(system: "s", messages: [ { role: "user", content: "q" } ], tools: [])

    expect(response.content).to eq([ { type: "text", text: "one" } ])
    expect(gateway.requests).to eq([ { system: "s", messages: [ { role: "user", content: "q" } ], tools: [], task: :chat_default, tool_choice: nil } ])
  end

  it "says so when the script is over, instead of inventing an answer" do
    expect { described_class.new([]).call(system: "s", messages: [], tools: []) }.to raise_error(Agent::FakeGateway::ScriptExhausted)
  end

  it "answers with a plain simulated text outside a script, so that the panel works on a development machine" do
    response = described_class.simulated.call(system: "s", messages: [], tools: [])

    expect(response.content.first[:text]).to include("simulated")
  end
end
