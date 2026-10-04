# F06 step 3: what the draft supplier invoice of a received document will be, worked out before anything is created, with every reason it cannot
# be (the document then waits for review). One line per VAT category and rate (document charges and allowances go to their category: the
# lines of an invoice cannot be negative, and a UBL document can have negative ones); the account of the supplier's last invoice, else the
# suspense account (the invoice cannot be posted until a person has coded it); the VAT treatment from the entity's mapping of the categories.
# => Plan(treatment, journal, lines, payment_reference, credited_invoice, problems, notes)
class Peppol::InvoicePlan
  Plan = Struct.new(:treatment, :journal, :lines, :payment_reference, :credited_invoice, :problems, :notes, keyword_init: true)
  PlannedLine = Struct.new(:description, :account, :amount, :vat_rate, :category, keyword_init: true)

  # `partner`: the supplier when it is already known (its defaults give the account, the journal), else nil.
  def self.build(canonical, partner: nil) = new(canonical, partner).build

  def initialize(canonical, partner)
    @invoice = canonical
    @partner = partner
    @problems = []
    @notes = []
  end

  def build
    Accounting::VatCategoryMapping.ensure_defaults!
    defaults = @partner && Accounting::SupplierDefault.find_by(partner_id: @partner.id)
    treatment = treatment_of
    lines = planned_lines(defaults)
    credited = credited_invoice
    Plan.new(treatment: treatment, journal: defaults&.journal, lines: lines, payment_reference: @invoice.payment[:id], credited_invoice: credited,
             problems: @problems, notes: @notes)
  end

  private

  def mappings = @mappings ||= Accounting::VatCategoryMapping.all.index_by(&:category)

  def categories = (@invoice.lines.map(&:tax_category) + @invoice.charges.map(&:tax_category)).compact.uniq

  # One treatment for the whole invoice: that of all its categories; ordinary purchases with an exempt or zero-rated part are domestic.
  def treatment_of
    unmapped = categories.reject { |c| mappings[c] }
    @problems << "The VAT categor#{unmapped.one? ? 'y' : 'ies'} #{unmapped.join(', ')} #{unmapped.one? ? 'is' : 'are'} not mapped to a VAT treatment (settings): the accountant decides" if unmapped.any?
    treatments = categories.filter_map { |c| mappings[c]&.vat_treatment }.uniq
    return treatments.first if treatments.size <= 1
    return "domestic" if (treatments - %w[domestic exempt]).empty?

    @problems << "The document mixes VAT treatments (#{treatments.join(', ')}): it has to be split by hand"
    nil
  end

  def planned_lines(defaults)
    suspense = Accounting::Account.find_by(code: Accounting::AccountCodes::TRANSIT)
    account = defaults&.account || suspense
    @problems << "No account to put the lines on: the entity has no suspense account #{Accounting::AccountCodes::TRANSIT}" unless account
    @notes << "Lines on the suspense account: to be coded before the invoice can be posted" if account && account == suspense

    groups = Hash.new { |h, k| h[k] = { amount: BigDecimal("0"), names: [] } }
    @invoice.lines.each { |l| groups[[ l.tax_category, l.tax_percent ]].tap { |g| g[:amount] += l.amount || 0; g[:names] << (l.name || l.description).to_s } }
    @invoice.charges.each { |c| groups[[ c.tax_category, c.tax_percent ]].tap { |g| g[:amount] += c.charge ? c.amount : -c.amount; g[:names] << (c.reason || (c.charge ? "Charge" : "Allowance")).to_s } }

    groups.filter_map do |(category, percent), group|
      next if group[:amount].zero?

      if group[:amount].negative?
        @problems << "The lines of VAT #{category} #{percent}% add up to #{group[:amount]}, which an invoice line cannot be: it is to be looked at"
        next
      end
      PlannedLine.new(description: describe(group[:names], category, percent), account: account, amount: group[:amount], vat_rate: rate_for(category, percent), category: category)
    end
  end

  def describe(names, category, percent)
    text = names.compact_blank.uniq.first(3).join(" · ")
    text = "#{@invoice.number} — VAT #{category} #{percent}%" if text.blank?
    text.truncate(240)
  end

  # The rate of the document, or the entity's rate for a treatment where the buyer self-assesses the VAT (the document carries none).
  def rate_for(category, percent) = mappings[category]&.vat_rate || percent

  # A credit note that names the invoice it corrects (BillingReference) is linked to it when that invoice is a posted one of the same supplier.
  def credited_invoice
    reference = @invoice.references[:billing]
    return unless @invoice.kind == :credit_note && reference.present? && @partner

    original = Accounting::Invoice.supplier.invoice.where(partner_id: @partner.id, supplier_reference: reference).where(status: %i[posted partially_paid paid]).first
    @notes << (original ? "Credit note of invoice #{reference}" : "The credit note refers to invoice #{reference}, which is not among the posted invoices of this supplier")
    original
  end
end
