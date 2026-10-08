# The checks of the server on what was read from a document (A09), none of them asking the model: the lines add up to the total excluding VAT, that plus the VAT is the total, each rate's base gives its
# VAT, the VAT number, the IBAN and the structured communication carry their check digits, the dates are plausible. Each field gets valid, invalid (with the reason) or unchecked; the document gets
# the checks that bear on several fields at once. An invalid field needs a person's confirmation.
class Agent::Documents::Validation
  TOLERANCE = BigDecimal("0.05") # the tolerance of the VAT consistency report (R09), per document
  Result = Struct.new(:fields, :document)

  # `fields`: name => canonical string value. `lines` and `breakdown`: as the model gave them (strings), already normalized by the caller. `today` for the plausibility of the dates.
  def self.call(fields, lines: [], breakdown: [], today: Date.current) = new(fields, lines, breakdown, today).call

  def initialize(fields, lines, breakdown, today)
    @fields = fields
    @lines = lines
    @breakdown = breakdown
    @today = today
  end

  def call
    Result.new(field_checks, document_checks)
  end

  private

  def field_checks
    @fields.to_h do |name, value|
      verdict = case name
      when "iban" then Accounting::Iban.valid?(value) ? ok : bad("not a valid IBAN (check digits)")
      when "supplier_vat" then vat(value)
      when "structured_communication" then Accounting::StructuredCommunication.extract(value) ? ok : bad("the check digits of the structured communication do not match")
      when "invoice_date", "due_date" then plausible_date(name, value)
      when "subtotal", "vat_amount", "total" then BigDecimal(value).negative? ? bad("negative amount") : ok
      else unchecked
      end
      [ name, verdict ]
    end
  end

  def vat(value)
    return bad("not a VAT number") unless value.match?(/\A[A-Z]{2}[A-Z0-9]{2,12}\z/)
    return unchecked("only Belgian numbers have their check digits verified here") unless value.start_with?("BE")

    Accounting::BelgianVatNumber.valid?(value) ? ok : bad("the check digits of the VAT number do not match")
  end

  def plausible_date(name, value)
    date = Date.iso8601(value)
    return bad("before the year 2000") if date.year < 2000
    return bad("more than a year ahead") if date > @today + 366
    return bad("the due date is before the invoice date") if name == "due_date" && @fields["invoice_date"] && Date.iso8601(@fields["invoice_date"]) > date

    ok
  rescue ArgumentError
    bad("not a date")
  end

  # => { "check name" => verdict }: the lines to the subtotal, the subtotal and the VAT to the total, each rate.
  def document_checks
    checks = {}
    sums = money(@lines.sum(BigDecimal("0")) { |line| BigDecimal(line["net"]) }) if @lines.any?
    checks["lines_add_up_to_subtotal"] = compare(sums, @fields["subtotal"], "the lines add up to #{sums}, the total excluding VAT is #{@fields['subtotal']}") if @lines.any? && @fields["subtotal"]
    if @fields["subtotal"] && @fields["vat_amount"] && @fields["total"]
      expected = money(BigDecimal(@fields["subtotal"]) + BigDecimal(@fields["vat_amount"]))
      checks["subtotal_plus_vat_is_total"] = compare(expected, @fields["total"], "total excluding VAT plus VAT is #{expected}, the total is #{@fields['total']}")
    end
    @breakdown.each do |row|
      expected = (BigDecimal(row["base"]) * BigDecimal(row["rate"]) / 100).round(2, half: :up)
      checks["vat_rate_#{row['rate']}"] = (expected - BigDecimal(row["vat"])).abs <= TOLERANCE ? ok : bad("#{row['rate']} percent of #{row['base']} is #{money(expected)}, the document says #{row['vat']}")
    end
    checks
  end

  def compare(expected, actual, reason) = (BigDecimal(expected) - BigDecimal(actual)).abs <= TOLERANCE ? ok : bad(reason)

  def money(amount) = Agent::ToolResult.money(amount)
  def ok = { "status" => "valid" }
  def bad(reason) = { "status" => "invalid", "reason" => reason }
  def unchecked(reason = nil) = { "status" => "unchecked", "reason" => reason }.compact
end
