require "rails_helper"

RSpec.describe Agent::Message do
  include_context "with entity"

  let(:conversation) { Agent::Conversation.create!(user: create(:user), title: "t") }

  it "keeps its content encrypted in the database" do
    message = conversation.messages.create!(role: "user", content: "Who owes me the most?")

    raw = ActiveRecord::Base.connection.select_value("SELECT content FROM agent_messages WHERE id = #{message.id}")

    expect(raw).not_to include("Who owes me")
    expect(message.reload.content).to eq("Who owes me the most?")
  end

  it "knows only the roles of the model's turns" do
    expect { conversation.messages.create!(role: "system", content: "x") }.to raise_error(ArgumentError)
  end

  it "records what it cost: model, tokens, latency and the version manifest" do
    message = conversation.messages.create!(role: "assistant", content: "42", model: "m-1", manifest_hash: "abc", input_tokens: 120, output_tokens: 8, latency_ms: 900)

    expect(message.reload).to have_attributes(model: "m-1", manifest_hash: "abc", input_tokens: 120, output_tokens: 8, latency_ms: 900)
  end

  it "is complete unless a generation was stopped or failed" do
    expect(conversation.messages.create!(role: "assistant", content: "ok").status).to eq("complete")
    expect(conversation.messages.create!(role: "assistant", content: "pa", status: "stopped")).to be_stopped
  end
end
