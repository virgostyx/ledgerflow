# The server's check of a note the agent proposes to remember (A10b): a short text about the whole file, a partner or an account of this entity, in a category, perhaps until a date. The agent never writes a note by
# itself: this is a proposal the person reads, corrects and confirms. => Result(errors:, warnings:, normalized:)
class Agent::Proposals::Note
  Result = Struct.new(:errors, :warnings, :normalized) do
    def valid? = errors.empty?
  end

  KEYS = %w[scope_kind object_id text category valid_until rationale].freeze

  def self.call(payload, context:, today: Date.current) = new(payload, context, today).call

  def initialize(payload, context, today)
    @payload = payload.to_h.deep_stringify_keys
    @context = context
    @today = today
    @errors = []
    @warnings = []
  end

  def call
    unknown = @payload.keys - KEYS
    @errors << "Unknown field(s): #{unknown.join(', ')}." if unknown.any?
    kind = @payload["scope_kind"]
    @errors << "scope_kind must be one of #{Agent::MemoryNote::SCOPES.join(', ')}." unless Agent::MemoryNote::SCOPES.include?(kind)
    @errors << "category must be one of #{Agent::MemoryNote::CATEGORIES.join(', ')}." unless Agent::MemoryNote::CATEGORIES.include?(@payload["category"])
    text = @payload["text"].to_s.gsub(Agent::Untrusted::HIDDEN, "").squish
    @errors << "text is required." if text.empty?
    @errors << "text is too long (#{Agent::MemoryNote::MAX_LENGTH} characters at most)." if text.length > Agent::MemoryNote::MAX_LENGTH
    object = check_object(kind)
    until_date = check_date
    @warnings << "The text looks like an instruction to an AI: it will be kept as text, with no effect." if Agent::InjectionDetector.scan(text).any?
    @warnings << "A note with the same text already exists for this object." if text.present? && duplicate?(kind, @payload["object_id"], text)
    @warnings << "A note is not a source of figures: do not put amounts in it that the books should give." if text.match?(Agent::Amounts::MONEY)
    Result.new(@errors, @warnings, (normalized(kind, object, text, until_date) if @errors.empty?))
  end

  private

  def check_object(kind)
    return if kind == "entity" || kind.nil?

    id = @payload["object_id"]
    object = { "partner" => Accounting::Partner, "account" => Accounting::Account }[kind]&.find_by(id: id)
    @errors << "object_id must be the ID of a #{kind} of this entity." unless object
    object
  end

  def check_date
    return if @payload["valid_until"].nil?

    date = Date.iso8601(@payload["valid_until"].to_s)
    @errors << "valid_until cannot be in the past." if date < @today
    date
  rescue ArgumentError
    @errors << "valid_until must be a date (YYYY-MM-DD)."
    nil
  end

  def duplicate?(kind, id, text)
    Agent::MemoryNote.active.for_scope(kind, kind == "entity" ? nil : id).any? { |note| note.text.squish.casecmp?(text) }
  end

  def normalized(kind, object, text, until_date)
    { "kind" => "note", "scope_kind" => kind, "object_id" => object&.id, "object_label" => object.try(:name) || object.try(:label_fr), "text" => text, "category" => @payload["category"],
      "valid_until" => until_date&.iso8601, "rationale" => @payload["rationale"].to_s.squish.first(500), "certainty" => "given", "warnings" => @warnings }.compact
  end
end
