require "rails_helper"

RSpec.describe Agent::ToolCall do
  include_context "with entity"

  let(:message) { Agent::Conversation.create!(user: create(:user), title: "t").messages.create!(role: "assistant", content: "x") }

  it "belongs to the answer, and goes with it" do
    message.tool_calls.create!(tool: "get_trial_balance", arguments: "{}", status: "ok")

    expect { message.destroy! }.to change(described_class, :count).by(-1)
  end

  it "needs a tool and an outcome, and knows only ok or error" do
    expect(described_class.new(message: message, status: "ok")).not_to be_valid
    expect(described_class.new(message: message, tool: "t")).not_to be_valid
    expect { described_class.new(message: message, tool: "t", status: "bad") }.to raise_error(ArgumentError)
  end
end
