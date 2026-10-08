# The reading of a text by the model, without any record (A09): the isolated call (one tool, forced, the masked text), the grounding of every value in the text, the checks of the server. The result is
# what Agent::Documents::Extract keeps, and what the evaluation of documents measures against the labels of its corpus. => Result, or an Error with the reason (nothing is kept then).
class Agent::Documents::Reading
  MAX_PAGES = 30

  Result = Struct.new(:type, :fields, :lines, :breakdown, :checks, :warnings, :sent, :usage, :model, :suspicious, :coverage, keyword_init: true)
  class Error < StandardError; end

  def self.call(text:, user:, gateway:) = new(text, user, gateway).call

  def initialize(text, user, gateway)
    @text = text.to_s
    @user = user
    @gateway = gateway
  end

  def call
    pages = @text.split("\f")
    read = pages.first(MAX_PAGES)
    suspicious = Agent::InjectionDetector.scan(read.join("\n")).any?
    submitted, response = ask(read)
    build(submitted, read.join("\f"), response, pages.size > MAX_PAGES ? "partial" : "full", suspicious)
  end

  private

  # The conversation only holds the tokens of the masking for the length of the call; the values come back unmasked, and it is deleted.
  def ask(pages)
    conversation = Agent::Conversation.create!(user: @user, title: "Document reading", origin_screen: Agent::Conversation::DOCUMENT_READING)
    redactor = Agent::Redactor.new(setting: Agent::Setting.for_current_entity, conversation: conversation)
    response = @gateway.call(system: Agent::Documents::Submission::SYSTEM, messages: [ { role: "user", content: "<document>\n#{pages.each_with_index.map { |page, i| "[page #{i + 1}]\n#{page}" }.join("\n\n")}\n</document>" } ],
                             tools: [ Agent::Documents::Submission.definition ], tool_choice: Agent::Documents::Submission.tool_choice, redactor: redactor)
    call = response.tool_uses.find { |use| use[:name] == Agent::Documents::Submission::NAME }
    raise Error, "The model did not answer in the expected form: nothing was kept." unless call

    [ reveal(call[:input].to_h.deep_stringify_keys, conversation), response ]
  ensure
    conversation&.destroy
  end

  def reveal(value, conversation)
    case value
    when Hash then value.transform_values { |inner| reveal(inner, conversation) }
    when Array then value.map { |inner| reveal(inner, conversation) }
    when String then conversation.reveal(value)
    else value
    end
  end

  def build(submitted, text, response, coverage, suspicious)
    grounding = Agent::Documents::Grounding.new(text)
    type = Agent::Documents::Submission::TYPES.include?(submitted["document_type"]) ? submitted["document_type"] : "other"
    fields = {}
    Agent::Documents::Submission::FIELD_NAMES.each do |name|
      given = submitted.dig("fields", name)
      next unless given.is_a?(Hash)

      canonical = Agent::Documents::Normalize.value(name, given["value"])
      found = canonical && grounding.find(name, canonical)
      fields[name] = found ? { "value" => canonical, "confidence" => Agent::Documents::Submission::CONFIDENCE.include?(given["confidence"]) ? given["confidence"] : "low", "page" => found.page, "snippet" => found.snippet } : { "state" => "not_found" }
    end
    lines = Array(submitted["lines"]).filter_map { |line| clean_line(line) }
    breakdown = Array(submitted["vat_breakdown"]).filter_map { |row| clean_row(row) }
    verdict = judge(fields, lines, breakdown)
    warnings = []
    warnings << "Only the first #{MAX_PAGES} pages were read: the rest of the document is not covered." if coverage == "partial"
    warnings << "The text of this document looks like an instruction to an AI: it was treated as data." if suspicious
    Result.new(type: type, fields: fields, lines: lines, breakdown: breakdown, checks: verdict.document, warnings: warnings, sent: response.sent, usage: response.usage, model: response.model, suspicious: suspicious, coverage: coverage)
  end

  # The state of each field after the checks of the server: ok, or needing a person.
  def judge(fields, lines, breakdown)
    values = fields.select { |_, field| field["value"] }.transform_values { |field| field["value"] }
    verdict = Agent::Documents::Validation.call(values, lines: lines, breakdown: breakdown)
    fields.each do |name, field|
      next if field["state"] == "not_found"

      field["validation"] = verdict.fields[name]
      field["state"] = field["confidence"] == "low" || field.dig("validation", "status") == "invalid" ? "needs_confirmation" : "ok"
    end
    # A check that bears on several amounts (the lines, the total, a rate) that fails puts all the amounts it bears on in doubt.
    if verdict.document.values.any? { |check| check["status"] == "invalid" }
      %w[subtotal vat_amount total].each { |name| fields[name]["state"] = "needs_confirmation" if fields[name] && fields[name]["state"] == "ok" }
    end
    verdict
  end

  def clean_line(line)
    return unless line.is_a?(Hash)

    net = Agent::Documents::Normalize.value("subtotal", line["net"])
    { "description" => line["description"].to_s.gsub(Agent::Untrusted::HIDDEN, "").first(200), "net" => net, "vat_rate" => line["vat_rate"].to_s.first(10).presence }.compact if net
  end

  def clean_row(row)
    return unless row.is_a?(Hash)

    base, vat = %w[base vat].map { |key| Agent::Documents::Normalize.value("subtotal", row[key]) }
    rate = row["rate"].to_s[/\A\d{1,2}(?:[.,]\d{1,2})?\z/]&.tr(",", ".")
    { "rate" => rate, "base" => base, "vat" => vat } if base && vat && rate
  end
end
