# The conversations as a file, for the person who had them or for an owner answering a request about a natural person (A04). The names come back as the person read them: the tokens of
# the model are replaced by what they stand for.
module Agent::Export
  def self.conversations(conversations, with_author: false)
    { "exported_at" => Time.current.iso8601,
      "conversations" => conversations.includes(:messages, :user, :proposals).order(:id).map { |conversation| conversation_hash(conversation, with_author) } }
  end

  def self.conversation_hash(conversation, with_author)
    { "title" => conversation.title, "started_at" => conversation.created_at.iso8601, "author" => (conversation.user.email if with_author),
      "messages" => conversation.messages.order(:id).map { |message| { "role" => message.role, "at" => message.created_at.iso8601, "status" => message.status, "content" => conversation.reveal(message.content) } },
      "proposals" => conversation.proposals.sort_by(&:id).map { |proposal| { "kind" => proposal.kind, "status" => proposal.status, "outcome" => proposal.outcome, "at" => proposal.created_at.iso8601, "proposal" => proposal.data } } }.compact
  end
  private_class_method :conversation_hash
end
