# The conversations of the entity that concern a person (A04): where they typed the name, where an answer carried it, where it was masked for the model (the pseudonym table knows it). The
# content is encrypted, so it is read and compared here, conversation by conversation: it is for an owner's request, not for every page, and the retention keeps the set small.
module Agent::SubjectSearch
  def self.conversations(name)
    wanted = name.to_s.squish.downcase
    return Agent::Conversation.none if wanted.length < 3

    ids = Agent::Conversation.includes(:pseudonyms, messages: %i[tool_calls feedbacks]).find_each.select { |conversation| concerns?(conversation, wanted) }.map(&:id)
    Agent::Conversation.where(id: ids)
  end

  def self.concerns?(conversation, wanted)
    messages = conversation.messages
    texts = messages.map(&:content) + conversation.pseudonyms.map(&:real_value) + messages.flat_map { |message| message.tool_calls.map(&:arguments) + message.feedbacks.map(&:comment) }
    texts.compact.any? { |text| text.downcase.include?(wanted) }
  end
  private_class_method :concerns?
end
