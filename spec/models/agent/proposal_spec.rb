require "rails_helper"

RSpec.describe Agent::Proposal do
  include_context "with entity"

  let(:user) { create(:user) }
  let(:conversation) { Agent::Conversation.create!(user: user, title: "t") }

  def proposal(**attrs) = described_class.create!({ user: user, conversation: conversation, kind: "entry_draft", payload: { "totals" => { "debit" => "10.00" } }.to_json }.merge(attrs))

  it "expires seven days after it was made, unless given another date" do
    expect(proposal.expires_at).to be_within(1.minute).of(7.days.from_now)
  end

  it "keeps its content encrypted at rest" do
    stored = ActiveRecord::Base.connection.select_value("SELECT payload FROM agent_proposals WHERE id = #{proposal.id}")

    expect(stored).not_to include("totals")
  end

  it "is decided by its author alone, while it waits and is not late" do
    waiting = proposal

    expect(waiting.decidable_by?(user)).to be true
    expect(waiting.decidable_by?(create(:user))).to be false
    expect(proposal(expires_at: 1.minute.ago).decidable_by?(user)).to be false
    expect(proposal(status: "rejected").decidable_by?(user)).to be false
  end

  it "turns the late ones into expired ones, and only those" do
    late = proposal(expires_at: 1.minute.ago)
    fresh = proposal

    described_class.expire_due!

    expect(late.reload).to be_expired
    expect(fresh.reload).to be_pending
  end

  it "is swept by the retention job too" do
    late = proposal(expires_at: 1.minute.ago)

    Agent::RetentionJob.perform_now

    expect(late.reload).to be_expired
  end

  it "knows its total, to compare with the review threshold" do
    expect(proposal.total).to eq(BigDecimal("10.00"))
  end
end
