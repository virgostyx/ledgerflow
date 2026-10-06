require "rails_helper"

RSpec.describe Agent::Feedback do
  include_context "with entity"

  let(:user)    { create(:user) }
  let(:message) { Agent::Conversation.create!(user: user, title: "t").messages.create!(role: "assistant", content: "42") }

  it "records useful or not useful, with a category and an encrypted comment" do
    feedback = described_class.create!(message: message, user: user, rating: "not_useful", category: "wrong_figure", comment: "The total is off")

    raw = ActiveRecord::Base.connection.select_value("SELECT comment FROM agent_feedback WHERE id = #{feedback.id}")

    expect(raw).not_to include("total is off")
    expect(feedback.reload).to have_attributes(rating: "not_useful", category: "wrong_figure", comment: "The total is off")
  end

  it "asks for a category only to say what was wrong" do
    expect(described_class.new(message: message, user: user, rating: "useful")).to be_valid
    expect(described_class.new(message: message, user: user, rating: "not_useful", category: "nonsense")).not_to be_valid
  end

  it "is given once per person and message" do
    described_class.create!(message: message, user: user, rating: "useful")

    expect(described_class.new(message: message, user: user, rating: "not_useful")).not_to be_valid
  end
end
