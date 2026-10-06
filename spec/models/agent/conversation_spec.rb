require "rails_helper"

RSpec.describe Agent::Conversation do
  include_context "with entity"

  let(:author) { create(:user) }
  let(:other)  { create(:user) }

  def conversation(user: author, **attrs) = described_class.create!({ user: user, title: "Aged balance" }.merge(attrs))

  it "belongs to the entity that was active when it was opened" do
    expect(conversation.entity).to eq(entity)
  end

  it "is visible to its author only, an owner of the entity included" do
    mine = conversation
    conversation(user: other)

    expect(described_class.visible_to(author)).to contain_exactly(mine)
  end

  it "does not leak across entities" do
    mine = conversation
    foreign = ActsAsTenant.with_tenant(create(:entity)) { described_class.create!(user: author, title: "Theirs") }

    expect(described_class.all).to contain_exactly(mine)
    expect(ActsAsTenant.without_tenant { described_class.all }).to include(foreign)
  end

  it "keeps the object it was opened on as a reference, never as copied text" do
    expect(conversation(context_ref: { "type" => "R04", "id" => "p-1042" }).context_ref).to eq("type" => "R04", "id" => "p-1042")
  end

  it "can be renamed and archived" do
    mine = conversation

    mine.update!(title: "Renamed")
    mine.archive!

    expect(mine.reload).to have_attributes(title: "Renamed", status: "archived")
    expect(mine.archived_at).to be_present
  end

  it "takes its messages with it when deleted" do
    mine = conversation
    mine.messages.create!(role: "user", content: "Hello")

    expect { mine.destroy! }.to change(Agent::Message, :count).by(-1)
  end
end
