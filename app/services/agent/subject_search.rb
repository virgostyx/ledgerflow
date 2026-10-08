# The conversations of the entity that concern a person (A04): where they typed the name, where an answer carried it, where it was masked for the model (the pseudonym table knows it). The
# content is encrypted, so it is read and compared here, conversation by conversation: it is for an owner's request, not for every page, and the retention keeps the set small.
module Agent::SubjectSearch
  def self.conversations(name)
    wanted = name.to_s.squish.downcase
    return Agent::Conversation.none if wanted.length < 3

    ids = Agent::Conversation.includes(:pseudonyms, messages: %i[tool_calls feedbacks]).find_each.select { |conversation| concerns?(conversation, wanted) }.map(&:id)
    Agent::Conversation.where(id: ids)
  end

  # The rest of what the assistant keeps that can name a person (A07, A09, A10): the notes of the memory, the summaries, the proposals and the readings of documents. All encrypted, so compared here, one by one.
  Related = Struct.new(:notes, :digests, :proposals, :extractions) do
    def count = to_a.sum(&:size)
    def any? = count.positive?
  end

  def self.related(name)
    wanted = name.to_s.squish.downcase
    return Related.new([], [], [], []) if wanted.length < 3

    partner_ids = Accounting::Partner.where("lower(name) LIKE ?", "%#{Accounting::Partner.sanitize_sql_like(wanted)}%").pluck(:id)
    notes = Agent::MemoryNote.all.select { |note| note.text.downcase.include?(wanted) || (note.scope_kind == "partner" && partner_ids.include?(note.scope_id)) }
    digests = Agent::Digest.all.select { |digest| digest.payload.downcase.include?(wanted) }
    proposals = Agent::Proposal.all.select { |proposal| proposal.payload.downcase.include?(wanted) || partner_ids.intersect?(proposal.data.fetch("lines", []).filter_map { |line| line["partner_id"] }) || (proposal.data["scope_kind"] == "partner" && partner_ids.include?(proposal.data["object_id"])) }
    extractions = Agent::DocumentExtraction.all.select { |extraction| extraction.payload.to_s.downcase.include?(wanted) }
    Related.new(notes, digests, proposals, extractions)
  end

  def self.concerns?(conversation, wanted)
    messages = conversation.messages
    texts = messages.map(&:content) + conversation.pseudonyms.map(&:real_value) + messages.flat_map { |message| message.tool_calls.map(&:arguments) + message.feedbacks.map(&:comment) }
    texts.compact.any? { |text| text.downcase.include?(wanted) }
  end
  private_class_method :concerns?
end
