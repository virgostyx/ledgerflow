# Where the amounts of an answer may come from (A05): a tool result of the answer (a calculation included), what the person typed, an earlier answer of the conversation. Anything else is an amount
# nobody gave. The agent computes nothing and invents nothing: an amount that is not anchored is regenerated once, then shown as unverified.
class Agent::Anchors
  MONEY_INPUT = /\A-?\d+\.\d{2}\z/
  # The dates and the invoice numbers of a text (A11), as they are written.
  DATE_WRITTEN = Regexp.union(Accounting::DocumentFieldParser::DATE_ISO, Accounting::DocumentFieldParser::DATE_NUMERIC, Accounting::DocumentFieldParser::DATE_DAY_MONTH, Accounting::DocumentFieldParser::DATE_MONTH_DAY)
  INVOICE_NUMBER = %r{\b[A-Z]{2,6}\d{4}/\d{3,6}\b|\b[A-Z]{1,4}-\d{4}-\d{2,6}\b}

  def initialize(question:, earlier_answers: [])
    @amounts = Set.new(Agent::Amounts.of(question) + earlier_answers.flat_map { |text| Agent::Amounts.of(text) })
    @references = Set.new(Agent::LegalReferences.keys(question) + earlier_answers.flat_map { |text| Agent::LegalReferences.keys(text) })
    @dates = Set.new
    @numbers = Set.new
    ([ question ] + earlier_answers).each { |text| learn(text) }
  end

  def add_result(json)
    @amounts.merge(Agent::Amounts.of(json))
    @references.merge(Agent::LegalReferences.keys(json))
    learn(json)
  end

  # The dates (ISO) and the invoice numbers of a draft that no source gave (A11): as spans of the text, to be put in place by a placeholder.
  def unanchored_dates(text) = spans(text, DATE_WRITTEN).reject { |_, date| @dates.include?(date) }.map(&:first)
  def unanchored_numbers(text) = spans(text, INVOICE_NUMBER).reject { |_, number| @numbers.include?(number) }.map(&:first)

  # The legal references of a text that neither a passage, nor the person, nor an earlier answer gave (A06).
  def unanchored_references(text) = Agent::LegalReferences.matches(text).reject { |match| @references.include?(match.key) }

  # The amounts of a text that no source gave.
  def unanchored(text) = Agent::Amounts.of(text) - @amounts.to_a

  # The values handed to a calculation that look like amounts (two decimals) and that no source gave. A value that is not shaped like an amount (a count, a rate with other decimals) is free, and so is
  # the second factor of a multiplication, which is a rate: `multiply` an anchored amount by 0.21 is a VAT calculation.
  def unanchored_inputs(values, operation: nil)
    checked = operation == "multiply" ? values.first(1) : values
    checked.select { |value| value.match?(MONEY_INPUT) }.map { |value| value.delete_prefix("-") }.reject { |value| @amounts.include?(value) }
  end

  private

  def learn(text)
    @dates.merge(spans(text, DATE_WRITTEN).map(&:last))
    @numbers.merge(text.to_s.scan(INVOICE_NUMBER))
  end

  # [[position, length], value] for each match; a date is given in ISO whatever its writing.
  def spans(text, pattern)
    text.to_s.to_enum(:scan, pattern).map { Regexp.last_match }.filter_map do |match|
      value = pattern == DATE_WRITTEN ? Accounting::DocumentFieldParser.parse_date(match[0]) : match[0]
      [ [ match.begin(0), match[0].length ], value ] if value
    end
  end
end
