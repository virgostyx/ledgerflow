# The server's check of a text the assistant drafts (A11): a reminder only for a customer who may be reminded, nothing in it that the policy of the company does not allow (interest, indemnity, a threat), nothing
# of an internal note in a text that leaves the company, a language the application writes, placeholders counted. The amounts, dates and invoice numbers are checked against the tools in the runner (it knows
# what the tools gave); the tokens of the masking too. => Result(errors:, warnings:, normalized:)
class Agent::Proposals::Text
  Result = Struct.new(:errors, :warnings, :normalized) do
    def valid? = errors.empty?
  end

  KEYS = %w[kind language subject body partner_id level facts revises].freeze
  MAX_BODY = 4000
  PLACEHOLDER = /\[To complete:[^\]]{1,80}\]/
  # What a reminder may only say when the policy of the company does: interest, an indemnity, a threat or a formal step.
  RISKS = {
    "late interest" => /interest|int[ée]r[êe]ts?|verwijlinteres|\brente\b/i,
    "a fixed indemnity" => /indemnit|indemnité|schadevergoeding|forfaitaire/i,
    "a threat or a legal step" => /bailiff|huissier|deurwaarder|legal (?:action|proceeding)|poursuite|rechtsvordering|gerechtelijk|lawyer|avocat|advocaat|\bcourt\b|tribunal|rechtbank|mise en demeure|ingebrekestelling|formal notice|recouvrement|recovery|inning/i
  }.freeze
  SENSITIVE = /deceased|death|bankrupt|bankruptcy|insolven|d[ée]c[èe]s|d[ée]c[ée]d|faillite|overleden|faillissement|\bdispute\b|litige|geschil/i

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
    kind = @payload["kind"]
    @errors << "kind must be one of #{Agent::TextDraft::KINDS.join(', ')}." unless Agent::TextDraft::KINDS.include?(kind)
    @errors << "language must be one of #{Agent::TextDraft::LANGUAGES.join(', ')}." unless Agent::TextDraft::LANGUAGES.include?(@payload["language"])
    body = @payload["body"].to_s.gsub(Agent::Untrusted::HIDDEN, "").strip
    @errors << "body is required." if body.empty?
    @errors << "body is too long (#{MAX_BODY} characters at most): give a shorter version." if body.length > MAX_BODY
    subject = @payload["subject"].to_s.squish.first(200).presence
    partner = check_partner
    check_dunning(partner, body) if kind == "dunning_letter" && partner
    check_leak(partner, body) if Agent::TextDraft::THIRD_PARTY.include?(kind) && body.present?
    check_revises
    facts = check_facts
    check_style(body)
    @warnings << "#{body.scan(PLACEHOLDER).size} placeholder(s) to fill before the text is used." if body.match?(PLACEHOLDER)
    @warnings << "The situation looks sensitive: the text is neutral, and should be read with care." if "#{subject} #{body}".match?(SENSITIVE)
    @warnings << "A text of the assistant is never sent by itself: a person reads it and sends it." if kind == "dunning_letter"
    Result.new(@errors, @warnings.uniq, (normalized(kind, subject, body, partner, facts) if @errors.empty?))
  end

  private

  def check_partner
    return if @payload["partner_id"].nil?

    partner = Accounting::Partner.find_by(id: @payload["partner_id"])
    @errors << "partner_id must be the ID of a partner of this entity." unless partner
    if partner && @payload["language"] != partner.language && Agent::TextDraft::LANGUAGES.include?(partner.language)
      @warnings << "The partner's language is #{partner.language}, the text is in #{@payload['language']}: say why, or write it in #{partner.language}."
    end
    partner
  end

  def check_dunning(partner, body)
    level = @payload["level"]
    @errors << "level must be 1, 2 or 3 for a reminder." unless Accounting::DunningPolicy::LEVELS.include?(level)
    facts = Agent::WritingFacts.for_partner(partner, as_of: @today)
    return @errors << "Refused: #{facts.blocked_reason} No reminder is written for this customer: explain why to the person." if facts.blocked_reason
    return unless Accounting::DunningPolicy::LEVELS.include?(level)

    standard = Accounting::DunningTexts.template(facts.policy, level, @payload["language"].presence_in(Accounting::DunningTexts::LANGUAGES) || "en").join(" ")
    RISKS.each do |what, pattern|
      next unless body.match?(pattern)
      next if what == "late interest" && facts.interest_enabled
      next if what == "a fixed indemnity" && facts.indemnity_enabled
      next if standard.match?(pattern)

      @errors << "The text mentions #{what}, which the reminder policy of the company does not allow at level #{level}. Take it out."
    end
    @warnings << "The reminder is level #{level} and the policy proposes level #{facts.level}: a higher level is the person's choice." if facts.level && level > facts.level
  end

  # A text that goes out of the company must not carry what the people of the file wrote for themselves: the notes of the memory, the comments of the tasks (six words in a row are enough to say it was copied).
  def check_leak(partner, body)
    internal = Agent::MemoryNote.active.where(scope_kind: "entity").or(Agent::MemoryNote.active.where(scope_kind: "partner", scope_id: partner&.id)).map(&:text)
    internal += Accounting::Comment.shown.limit(500).pluck(:body)
    shingles = ->(text) { words = text.to_s.downcase.scan(/[[:alnum:]']+/); words.each_cons(6).map { |chunk| chunk.join(" ") } }
    mine = shingles.call(body).to_set
    @errors << "The text repeats what an internal note or comment says. A text for a third party never reuses them, unless the person quotes them: take it out." if internal.any? { |text| shingles.call(text).any? { |chunk| mine.include?(chunk) } }
  end

  def check_revises
    return if @payload["revises"].nil?

    draft = Agent::TextDraft.find_by(id: @payload["revises"], user_id: @context.user.id)
    @errors << "revises must be the ID of one of the person's drafts that is still a draft." unless draft&.draft?
  end

  # Each fact is a label, a value, and where it comes from; one with a reference that does not open anything is dropped.
  def check_facts
    Array(@payload["facts"]).first(30).filter_map do |fact|
      next unless fact.is_a?(Hash) && fact["label"].present? && fact["value"].present?

      ref = fact["ref"].to_s.presence
      if ref && !(Agent::Refs.path(ref) || Agent::Refs.computed?(ref))
        @warnings << "A source was not recognised and left out: #{ref}."
        ref = nil
      end
      { "label" => fact["label"].to_s.first(80), "value" => fact["value"].to_s.first(120), "ref" => ref }.compact
    end
  end

  # The profile of the company: its closing formula, its signature, its length. Said, never silently corrected.
  def check_style(body)
    profile = Agent::Setting.find_by(entity: ActsAsTenant.current_tenant)&.writing_profile.to_h
    return if profile.empty?

    @warnings << "The closing formula of the company's profile is not in the text." if profile["closing"].present? && !body.downcase.include?(profile["closing"].to_s.downcase.first(40))
    @warnings << "The text is longer than the target of the profile (#{profile['length_words']} words)." if profile["length_words"].to_i.positive? && body.split.size > profile["length_words"].to_i * 1.5
  end

  def normalized(kind, subject, body, partner, facts)
    { "kind" => "text", "text_kind" => kind, "language" => @payload["language"], "subject" => subject, "body" => body, "partner_id" => partner&.id, "level" => @payload["level"], "facts" => facts,
      "revises" => @payload["revises"], "warnings" => @warnings }.compact
  end
end
