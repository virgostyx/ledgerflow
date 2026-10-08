# A value the model gives for a field of a document must be in the document (A09). The model reads a text; what it writes back is checked against that text, in the way the field is written there: an amount
# in any of the ways amounts are written, a date in any of the ways dates are, an identifier without its spaces and dots, a name without accents or case. A value that is not found is not kept, and the field
# says "not found in the document". The page and the line shown to the person are found here, in the text, never taken from what the model says it saw.
class Agent::Documents::Grounding
  DATE_PATTERNS = [ Accounting::DocumentFieldParser::DATE_ISO, Accounting::DocumentFieldParser::DATE_NUMERIC, Accounting::DocumentFieldParser::DATE_DAY_MONTH, Accounting::DocumentFieldParser::DATE_MONTH_DAY ].freeze
  CURRENCY_SYMBOLS = { "EUR" => "€", "USD" => "$", "GBP" => "£", "CHF" => "CHF" }.freeze
  Found = Struct.new(:page, :snippet)

  # `text`: the pages separated by a form feed, as F03 keeps them.
  def initialize(text)
    @pages = text.to_s.split("\f")
    @lines = @pages.each_with_index.flat_map { |page, index| page.lines.map(&:strip).reject(&:empty?).map { |line| [ line, index + 1 ] } }
  end

  # => Found (page and line where the value stands), or nil when it is not in the document. `value` is in its canonical form (see Agent::Documents::Normalize).
  def find(field, value)
    return if value.blank?

    case field
    when "subtotal", "vat_amount", "total" then amount(value)
    when "invoice_date", "due_date" then date(value)
    when "iban", "supplier_vat", "structured_communication", "invoice_number" then identifier(value)
    when "currency" then currency(value)
    when "supplier_name" then name(value)
    else loose(value)
    end
  end

  private

  def amount(value)
    @lines.each do |line, page|
      line.scan(Accounting::DocumentFieldParser::AMOUNT).flatten.each do |raw|
        parsed = Accounting::DocumentFieldParser.parse_amount(raw)
        return Found.new(page, line) if parsed && format("%.2f", parsed) == value
      end
    end
    nil
  end

  def date(value)
    @lines.each do |line, page|
      DATE_PATTERNS.each do |pattern|
        line.to_enum(:scan, pattern).map { Regexp.last_match[0] }.each { |raw| return Found.new(page, line) if Accounting::DocumentFieldParser.parse_date(raw) == value }
      end
    end
    nil
  end

  def identifier(value)
    wanted = squash(value)
    return if wanted.length < 3

    @lines.each { |line, page| return Found.new(page, line) if squash(line).include?(wanted) }
    nil
  end

  def currency(value)
    symbol = CURRENCY_SYMBOLS[value.upcase]
    @lines.each { |line, page| return Found.new(page, line) if line.upcase.include?(value.upcase) || (symbol && line.include?(symbol)) }
    nil
  end

  def name(value)
    wanted = fold(value)
    return if wanted.length < 2

    @lines.each { |line, page| return Found.new(page, line) if fold(line).include?(wanted) }
    nil
  end

  def loose(value)
    wanted = fold(value)
    @lines.each { |line, page| return Found.new(page, line) if fold(line).include?(wanted) }
    nil
  end

  def squash(text) = text.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  def fold(text) = I18n.transliterate(text.to_s).downcase.gsub(/\s+/, " ").strip
end
