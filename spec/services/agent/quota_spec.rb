require "rails_helper"

RSpec.describe Agent::Quota do
  include_context "with entity"

  let(:user)  { create(:user) }
  let(:other) { create(:user) }
  let(:limits) { { per_hour: 2, per_day: 3, concurrent_per_entity: 2 } }

  def ask(person = user, at: Time.current)
    conversation = Agent::Conversation.find_or_create_by!(user: person, title: "q")
    conversation.messages.create!(role: "user", content: "hi", created_at: at)
  end

  def check(person = user) = described_class.check(user: person, entity: entity, limits: limits)

  it "lets in a person who is under every limit" do
    ask

    expect(check).to be_nil
  end

  it "refuses once the questions of the last hour are used up, for that person only" do
    2.times { ask }

    expect(check).to eq(:per_hour)
    expect(check(other)).to be_nil
  end

  it "counts the day apart from the hour" do
    3.times { |i| ask(at: (2 + i).hours.ago) }

    expect(check).to eq(:per_day)
  end

  it "forgets what is more than a day old" do
    3.times { ask(at: 25.hours.ago) }

    expect(check).to be_nil
  end

  it "does not count the answers of the model, nor the questions of another entity" do
    Agent::Conversation.create!(user: user, title: "x").messages.create!(role: "assistant", content: "hi")
    ActsAsTenant.with_tenant(create(:entity)) { 3.times { Agent::Conversation.create!(user: user, title: "z").messages.create!(role: "user", content: "hi") } }

    expect(check).to be_nil
  end

  it "refuses when the entity already has as many answers being written as it may" do
    2.times { Agent::Conversation.create!(user: create(:user), title: "busy", answering_since: 10.seconds.ago) }

    expect(check).to eq(:busy)
  end

  it "does not count an answer that has been 'being written' for minutes: its job died" do
    2.times { Agent::Conversation.create!(user: create(:user), title: "dead", answering_since: 10.minutes.ago) }

    expect(check).to be_nil
  end

  it "says it to a person in words, with the limit" do
    expect(described_class.message(:per_hour, limits)).to include("2 questions per hour")
    expect(described_class.message(:per_day, limits)).to include("3 questions per day")
    expect(described_class.message(:busy, limits)).to include("busy")
  end
end
