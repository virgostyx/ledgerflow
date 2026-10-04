# The automatic checks of a received invoice (docs/dev/features/spec.md §9): the lines add up, the total without VAT is the lines plus the
# charges less the allowances, the VAT is the rate applied to the taxable amount of each category (within one cent), the total with VAT is the
# two added, a Belgian VAT number has the right check digits (modulo 97), the currency is a supported ISO one, the due date does not precede the
# issue date. => the list of problems, in words a person can act on (empty: nothing wrong). A document with a problem is not drafted.
class Peppol::InvoiceChecks
  TOLERANCE = BigDecimal("0.01")

  def self.call(invoice) = new(invoice).call

  def initialize(invoice)
    @invoice = invoice
    @problems = []
  end

  def call
    header
    parties
    amounts
    @problems
  end

  # Modulo 97 on a Belgian VAT number (BE + 10 digits): the last two digits are 97 less the remainder of the first eight.
  def self.belgian_vat_valid?(vat)
    digits = vat.to_s[/\ABE(\d{10})\z/, 1] or return false
    97 - (digits[0, 8].to_i % 97) == digits[8, 2].to_i
  end

  private

  def problem(text) = @problems << text

  def close?(left, right) = left && right && (left - right).abs <= TOLERANCE

  def header
    problem("The document has no number") if @invoice.number.blank?
    problem("The document has no issue date") unless @invoice.issue_date
    problem("The currency #{@invoice.currency.inspect} is not a supported ISO currency") unless Accounting::MoneyPresenter::SUPPORTED_CURRENCIES.include?(@invoice.currency)
    problem("The due date (#{@invoice.due_date}) is before the issue date (#{@invoice.issue_date})") if @invoice.due_date && @invoice.issue_date && @invoice.due_date < @invoice.issue_date
  end

  def parties
    vat = @invoice.supplier&.vat
    problem("The Belgian VAT number #{vat} of the supplier is not valid (check digits)") if vat.to_s.start_with?("BE") && !self.class.belgian_vat_valid?(vat)
  end

  def amounts
    totals = @invoice.totals
    lines = @invoice.lines
    problem("The document has no invoice line") if lines.empty?
    if totals.tax_exclusive.nil? || totals.tax_inclusive.nil?
      return problem("The document has no totals (TaxExclusiveAmount, TaxInclusiveAmount): they cannot be checked")
    end

    lines_sum = lines.sum { |l| l.amount || 0 }
    charges = @invoice.charges.select(&:charge).sum(&:amount)
    allowances = @invoice.charges.reject(&:charge).sum(&:amount)
    problem("The lines add up to #{lines_sum}, the document says #{totals.lines} (LineExtensionAmount)") if totals.lines && !close?(lines_sum, totals.lines)
    expected = lines_sum + charges - allowances
    problem("The lines, charges and allowances give #{expected}, the document says #{totals.tax_exclusive} (TaxExclusiveAmount)") unless close?(expected, totals.tax_exclusive)
    problem("The charges add up to #{charges}, the document says #{totals.charge} (ChargeTotalAmount)") if totals.charge && !close?(charges, totals.charge)
    problem("The allowances add up to #{allowances}, the document says #{totals.allowance} (AllowanceTotalAmount)") if totals.allowance && !close?(allowances, totals.allowance)
    vat_by_category
    vat_total(totals)
    problem("The document is negative (#{totals.tax_inclusive}): a negative invoice is a credit note, it is to be looked at") if @invoice.kind == :invoice && totals.tax_inclusive.negative?
  end

  # For each category and rate: the lines and the document charges less allowances of that category give the taxable amount, and the VAT is the
  # rate applied to it.
  def vat_by_category
    taxable = Hash.new(BigDecimal("0"))
    @invoice.lines.each { |l| taxable[[ l.tax_category, l.tax_percent ]] += l.amount || 0 }
    @invoice.charges.each { |c| taxable[[ c.tax_category, c.tax_percent ]] += (c.charge ? c.amount : -c.amount) }
    declared = @invoice.tax_subtotals.index_by { |s| [ s.category, s.percent ] }

    taxable.each do |(category, percent), expected|
      label = "VAT #{category} #{percent}%"
      subtotal = declared[[ category, percent ]]
      next problem("#{label}: #{expected} is taxable but the document has no tax subtotal for it") unless subtotal

      problem("#{label}: the taxable amount is #{expected}, the document says #{subtotal.taxable}") unless close?(expected, subtotal.taxable)
      computed = (subtotal.taxable.to_d * percent.to_d / 100).round(2, half: :up) if subtotal.taxable
      problem("#{label}: #{percent}% of #{subtotal.taxable} is #{computed}, the document says #{subtotal.tax}") unless computed && close?(computed, subtotal.tax)
    end
    declared.each_key { |key| problem("VAT #{key[0]} #{key[1]}%: declared, but no line carries it") unless taxable.key?(key) || declared[key].taxable.to_d.zero? }
  end

  def vat_total(totals)
    subtotals = @invoice.tax_subtotals.sum { |s| s.tax || 0 }
    problem("The VAT of the categories adds up to #{subtotals}, the document says #{@invoice.tax_total} (TaxAmount)") if @invoice.tax_total && !close?(subtotals, @invoice.tax_total)
    vat = @invoice.tax_total || subtotals
    problem("The total without VAT #{totals.tax_exclusive} plus the VAT #{vat} is not the total with VAT #{totals.tax_inclusive} (TaxInclusiveAmount)") unless close?(totals.tax_exclusive + vat, totals.tax_inclusive)
  end
end
