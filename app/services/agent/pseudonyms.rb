# The tokens of one conversation (A04): a person's name becomes PERSONNE_017, a VAT number TVA_003, the same token every time in the conversation. The table is encrypted, belongs to the
# conversation and is never sent to the model; it is what turns the tokens of an answer back into what the person knows.
class Agent::Pseudonyms
  PREFIX = { "person" => "PERSONNE", "tax_identifier" => "TVA" }.freeze
  TOKEN = /\b(?:PERSONNE|TVA)_\d{3,}\b/

  def initialize(conversation)
    @conversation = conversation
  end

  # The token of a value, created the first time. A value is the same value when it is written the same way.
  def token_for(value, kind)
    value = value.to_s.strip
    existing = by_value[[ kind, value ]]
    return existing.token if existing

    create(value, kind).token
  end

  # The text as the person reads it: every known token replaced by what it stands for. A token that is not in the table is left as it is.
  def reveal(text)
    return text if text.blank? || !text.match?(TOKEN)

    text.gsub(TOKEN) { |token| by_token[token]&.real_value || token }
  end

  # The tokens of a text that the table does not know: the model invented them.
  def unknown_tokens(text) = text.to_s.scan(TOKEN).uniq.reject { |token| by_token.key?(token) }

  private

  def rows = @rows ||= @conversation.pseudonyms.to_a
  def by_value = @by_value ||= rows.index_by { |row| [ row.kind, row.real_value ] }
  def by_token = @by_token ||= rows.index_by(&:token)

  def create(value, kind)
    number = rows.count { |row| row.kind == kind } + 1
    row = @conversation.pseudonyms.create!(kind: kind, real_value: value, token: format("%s_%03d", PREFIX.fetch(kind), number))
    rows << row
    by_value[[ kind, value ]] = row
    by_token[row.token] = row
  rescue ActiveRecord::RecordNotUnique # another request of the conversation took the number or the value first
    @rows = @by_value = @by_token = nil
    by_value.fetch([ kind, value ]) { create(value, kind) }
  end
end
