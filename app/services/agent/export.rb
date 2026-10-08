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
  # What else concerns a person (A07, A09, A10): their notes, the summaries and proposals and readings that name them.
  def self.related(related)
    { "notes" => related.notes.map { |note| { "about" => note.label, "text" => note.text, "written_on" => note.created_at.to_date.iso8601 } },
      "summaries" => related.digests.map { |digest| { "title" => digest.title, "content" => digest.data["sections"] } },
      "proposals" => related.proposals.map { |proposal| { "kind" => proposal.kind, "status" => proposal.status, "proposal" => proposal.data } },
      "document_readings" => related.extractions.map { |extraction| { "document" => extraction.document.name, "status" => extraction.status, "fields" => extraction.fields } } }
  end

  # The notes of the memory of the file, with who wrote them (A10b).
  def self.memory(notes)
    { "exported_at" => Time.current.iso8601,
      "notes" => notes.map { |note| { "about" => note.label, "category" => note.category, "text" => note.text, "author" => note.author.full_name, "written_on" => note.created_at.to_date.iso8601, "valid_until" => note.valid_until&.iso8601,
                                     "status" => note.status, "source" => note.source, "uses" => note.uses_count } } }
  end

  private_class_method :conversation_hash
end
