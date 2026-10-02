# Reads, from the text of an invoice, the fields an accountant would key in (F03). Everything is a PROPOSAL: each
# field keeps the line and the page it came from so that a person can check it, the numbers that carry check digits
# are validated (IBAN, Belgian VAT number, structured communication), and the amounts are cross-checked.
# Labels are read in English, French and Dutch. Pages are separated by a form feed.
class Accounting::DocumentFieldParser
  MONTHS = {
    "january" => 1, "janvier" => 1, "januari" => 1, "jan" => 1, "february" => 2, "fevrier" => 2, "februari" => 2, "feb" => 2,
    "march" => 3, "mars" => 3, "maart" => 3, "mar" => 3, "april" => 4, "avril" => 4, "apr" => 4, "may" => 5, "mai" => 5, "mei" => 5,
    "june" => 6, "juin" => 6, "juni" => 6, "jun" => 6, "july" => 7, "juillet" => 7, "juli" => 7, "jul" => 7,
    "august" => 8, "aout" => 8, "augustus" => 8, "aug" => 8, "september" => 9, "septembre" => 9, "sep" => 9, "sept" => 9,
    "october" => 10, "octobre" => 10, "oktober" => 10, "oct" => 10, "okt" => 10, "november" => 11, "novembre" => 11, "nov" => 11,
    "december" => 12, "decembre" => 12, "dec" => 12
  }.freeze

  # Accented letters are written `.`: a character class like [ée] does not match an upper-case É under /i.
  DATE_LABELS_DUE     = /due date|payment due|pay by|.ch.ance|vervaldatum|payable (?:avant|le)|. payer avant|te betalen voor|date limite/i
  DATE_LABELS_INVOICE = /invoice date|issue date|date de facture|date d.?.mission|factuurdatum|datum factuur|facturatiedatum/i
  LABEL_SUBTOTAL = /excl\.?\s*(?:vat|btw|tva)|\bhtva\b|hors\s+tva|\bht\b|sub-?total|net amount|maatstaf|tax exclusive|exclusive of vat|zonder btw/i
  LABEL_TOTAL    = /incl\.?\s*(?:vat|btw|tva)|\btvac\b|\bttc\b|amount due|montant\s+(?:.\s+payer|d.)|te betalen|.\s+payer|grand total|total\s+(?:due|to pay)|tax inclusive|inclusive of vat|inclusief btw|\btotaal\b|\btotal\b/i
  LABEL_VAT      = /\b(?:vat|btw|tva)\b/i
  NUMBER_WORD    = /(?:no\.?|n°|nº|nr\.?|number|nummer|num.ro|#)/i
  AMOUNT = /(?<![\d.,])(\d{1,3}(?:[ .,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)(?!\d)(?!\s*%)/
  DATE_NUMERIC = %r{(?<!\d)(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})(?!\d)}
  DATE_ISO     = /(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)/
  DATE_DAY_MONTH = /(?<!\d)(\d{1,2})(?:st|nd|rd|th|er)?\s+([[:alpha:]]+)\.?,?\s+(\d{4})/
  DATE_MONTH_DAY = /([[:alpha:]]+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})/
  IBAN_CANDIDATE = /\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){2,7}(?:\s?[A-Z0-9]{1,3})?\b/
  BE_VAT         = /\bBE\s?[01]\d{3}[.\s]?\d{3}[.\s]?\d{3}\b/
  STRUCTURED     = %r{\+{3}\s*(\d{3})\s*/\s*(\d{4})\s*/\s*(\d{5})\s*\+{3}}

  def self.call(text) = new(text).call

  # The same readers, for a value a person types: a decimal amount ("1.234,56", "1234.56"...) or a date, or nil.
  def self.parse_amount(text) = new("").send(:normalize_amount, text.to_s.strip)
  def self.parse_date(text) = new("").send(:parse_date, text.to_s)

  # The supplier is named only when a partner of this entity has that VAT number: never guessed.
  def self.partner_fields(vat)
    return {} unless vat

    partner = Accounting::Partner.where("REPLACE(REPLACE(UPPER(vat_number), ' ', ''), '.', '') = ?", vat[:value]).first
    return {} unless partner

    { supplier_partner_id: { value: partner.id, snippet: vat[:snippet], page: vat[:page], confidence: :high },
      supplier_name: { value: partner.name, snippet: vat[:snippet], page: vat[:page], confidence: :high } }
  end

  def initialize(text)
    @pages = text.to_s.split("\f")
  end

  def call
    return {} if @pages.all?(&:blank?)

    fields = {}
    fields.merge!(number_and_dates)
    fields.merge!(amounts)
    fields.merge!(identifiers)
    fields
  end

  private

  # [line, page] for every non-blank line.
  def lines
    @lines ||= @pages.each_with_index.flat_map { |page, i| page.lines.map(&:strip).reject(&:empty?).map { |line| [ line, i + 1 ] } }
  end

  def field(value, line, page, confidence) = { value: value, snippet: line, page: page, confidence: confidence }

  # --- invoice number and dates ---------------------------------------------------------------------------------

  def number_and_dates
    found = {}
    lines.each do |line, page|
      next if found.key?(:invoice_number)

      number, explicit = invoice_number_in(line)
      found[:invoice_number] = field(number, line, page, explicit ? :high : :low) if number
    end
    found.merge!(dates)
  end

  def invoice_number_in(line)
    match = line.match(/(?<!date de )(?<!datum )\b(?:invoice|facture|factuur|rechnung)\s*(#{NUMBER_WORD})?\s*[:#]?\s*([A-Z0-9][A-Z0-9\-\/._]*\d[A-Z0-9\-\/._]*)/i)
    return unless match
    return if parse_date(match[2])

    [ match[2].sub(/[.,]\z/, ""), match[1].present? ]
  end

  def dates
    found = {}
    lines.each do |line, page|
      date = first_date(line)
      next unless date

      if line.match?(DATE_LABELS_DUE)
        found[:due_date] ||= field(date, line, page, :high)
      elsif line.match?(DATE_LABELS_INVOICE) || line.match?(/\A(?:date|datum)\s*[:.]/i)
        found[:invoice_date] ||= field(date, line, page, :high)
      end
    end
    unless found.key?(:invoice_date)
      lines.each do |line, page|
        date = first_date(line)
        next unless date && !line.match?(DATE_LABELS_DUE)

        found[:invoice_date] = field(date, line, page, :low)
        break
      end
    end
    found
  end

  def first_date(text)
    parse_date(text)
  end

  # An ISO date, or nil: impossible dates (31/02) are refused.
  def parse_date(text)
    if (m = text.match(DATE_ISO)) then iso(m[1], m[2], m[3])
    elsif (m = text.match(DATE_NUMERIC)) then iso(m[3], m[2], m[1])
    elsif (m = text.match(DATE_DAY_MONTH)) && month(m[2]) then iso(m[3], month(m[2]), m[1])
    elsif (m = text.match(DATE_MONTH_DAY)) && month(m[1]) then iso(m[3], month(m[1]), m[2])
    end
  end

  def month(word) = MONTHS[I18n.transliterate(word.to_s).downcase]

  def iso(year, month, day)
    year, month, day = year.to_i, month.to_i, day.to_i
    format("%04d-%02d-%02d", year, month, day) if Date.valid_date?(year, month, day)
  end

  # --- amounts -------------------------------------------------------------------------------------------------

  # Totals sit at the end of an invoice, so the LAST labelled line of each kind is the one that counts.
  def amounts
    labelled = { subtotal: nil, total: nil, vat_amount: nil }
    lines.each do |line, page|
      next if line.match?(BE_VAT) && !line.match?(LABEL_TOTAL) && !line.match?(LABEL_SUBTOTAL) # a VAT number line is not an amount

      kind = if line.match?(LABEL_SUBTOTAL) then :subtotal
      elsif line.match?(LABEL_TOTAL) then :total
      elsif line.match?(LABEL_VAT) then :vat_amount
      end
      next unless kind

      amount = line.scan(AMOUNT).flatten.last
      value = amount && normalize_amount(amount)
      labelled[kind] = [ value, line, page ] if value
    end
    consistent = labelled.values.all? && (labelled[:subtotal][0] + labelled[:vat_amount][0] - labelled[:total][0]).abs <= BigDecimal("0.02")
    confidence = consistent ? :high : :low
    labelled.compact.to_h { |kind, (value, line, page)| [ kind, field(format("%.2f", value), line, page, confidence) ] }
  end

  # "1.234,56", "1,234.56", "1 234,56", "1234.56", "1234,5" -> BigDecimal
  def normalize_amount(token)
    token = token.delete(" ")
    both = token.include?(".") && token.include?(",")
    separators = token.scan(/[.,]/)
    decimal = if both then token[/[.,](?=\d{1,2}\z)/]
    elsif separators.size == 1 && token.match?(/[.,]\d{1,2}\z/) then separators.first
    end
    if decimal
      whole, fraction = token.rpartition(decimal).then { |a, _, b| [ a, b ] }
      BigDecimal("#{whole.delete('.,')}.#{fraction}")
    else
      BigDecimal(token.delete(".,"))
    end
  rescue ArgumentError
    nil
  end

  # --- numbers that carry check digits ----------------------------------------------------------------------------

  def identifiers
    found = {}
    lines.each do |line, page|
      found[:iban] ||= iban_in(line, page)
      found[:supplier_vat] ||= vat_in(line, page)
      found[:structured_communication] ||= communication_in(line, page)
    end
    found.compact.merge(self.class.partner_fields(found[:supplier_vat]))
  end

  def iban_in(line, page)
    line.scan(IBAN_CANDIDATE).each do |candidate|
      return field(Accounting::Iban.normalize(candidate), line, page, :high) if Accounting::Iban.valid?(candidate)
    end
    nil
  end

  def vat_in(line, page)
    line.scan(BE_VAT).each do |candidate|
      number = candidate.upcase.gsub(/[\s.]/, "")
      return field(number, line, page, :high) if Accounting::BelgianVatNumber.valid?(number)
    end
    nil
  end

  def communication_in(line, page)
    match = line.match(STRUCTURED)
    return unless match && Accounting::StructuredCommunication.valid?(match[1] + match[2] + match[3])

    field("+++#{match[1]}/#{match[2]}/#{match[3]}+++", line, page, :high)
  end
end
