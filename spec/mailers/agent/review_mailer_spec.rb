require "rails_helper"

RSpec.describe Agent::ReviewMailer do
  include_context "with entity"

  let(:owner)  { create(:user, email: "owner@firm.test") }
  let(:author) { create(:user, email: "author@firm.test") }
  let(:conversation) { Agent::Conversation.create!(user: author, title: "Secret title") }
  let(:review) { Agent::ConversationReview.create!(conversation: conversation, author: author, reviewer: owner, reason: "Complaint about an answer", message_count: 4, reviewed_at: Time.zone.local(2026, 10, 7, 9, 30)) }

  subject(:mail) { described_class.conversation_read(review) }

  it "goes to the author, and says who read the conversation, when and why" do
    expect(mail.to).to eq([ "author@firm.test" ])
    expect(mail.subject).to include("conversation was read", entity.legal_name)
    expect(mail.body.encoded).to include("owner@firm.test", "Complaint about an answer", "2026")
  end

  it "does not repeat what was in the conversation, not even its title" do
    expect(mail.body.encoded).not_to include("Secret title")
  end
end
