# What can be checked offline of an UBL document we are about to send, before the Access Point sees it: the arithmetic and VAT checks of a received
# invoice (Peppol::InvoiceChecks) and the mandatory content of Peppol BIS Billing 3.0 / EN 16931 that our own builder can get wrong (the rules are
# named as in the specification: BR-xx, BR-S/E/AE/..., BR-CO-25, PEPPOL-R0xx).
#
# THIS IS NOT THE OFFICIAL SCHEMATRON. It is a subset, written by hand, of the rules that matter for what this application sends: a document that
# passes is not certified, and the Access Point still validates it. A refusal here is certain (the rule is broken); a pass is not a guarantee.
# => the problems, in words a person can act on (empty: nothing found)
class Peppol::UblRules
  CATEGORIES_NEEDING_A_REASON = %w[E AE K G O].freeze

  def self.call(xml) = new(xml).call

  def initialize(xml)
    @xml = xml
    @problems = []
  end

  def call
    @doc = Nokogiri::XML(@xml) { |c| c.strict }
    @doc.remove_namespaces!
    @canonical = Peppol::InvoiceMapper.call(@xml)
    @problems.concat(Peppol::InvoiceChecks.call(@canonical))
    identification
    parties
    lines
    vat
    payment
    @problems.uniq
  rescue Nokogiri::XML::SyntaxError, Peppol::InvoiceMapper::Unreadable => e
    [ "The document is not valid UBL: #{e.message.lines.first.to_s.strip}" ]
  end

  private

  def rule(id, text) = @problems << "#{id}: #{text}"

  def text(path) = @doc.at_xpath(path)&.text.to_s.strip.presence

  def identification
    rule("PEPPOL-R001", "the CustomizationID is not the one of Peppol BIS Billing 3.0") unless text("/*/CustomizationID") == Peppol::UblInvoiceBuilder::CUSTOMIZATION_ID
    rule("PEPPOL-R003", "the ProfileID is not the one of Peppol BIS Billing 3.0") unless text("/*/ProfileID") == Peppol::UblInvoiceBuilder::PROFILE_ID
    rule("BR-02", "an invoice needs a number") if @canonical.number.blank?
    rule("BR-03", "an invoice needs an issue date") unless @canonical.issue_date
  end

  def parties
    { "seller" => "AccountingSupplierParty", "buyer" => "AccountingCustomerParty" }.each do |who, tag|
      base = "/*/#{tag}/Party"
      rule(who == "seller" ? "BR-06" : "BR-07", "the #{who} needs a name") if text("#{base}/PartyLegalEntity/RegistrationName").nil? && text("#{base}/PartyName/Name").nil?
      rule(who == "seller" ? "BR-09" : "BR-11", "the #{who} needs a country in its address") if text("#{base}/PostalAddress/Country/IdentificationCode").nil?
      endpoint = @doc.at_xpath("#{base}/EndpointID")
      rule(who == "seller" ? "PEPPOL-R020" : "PEPPOL-R010", "the #{who} needs a Peppol endpoint identifier (with its scheme)") unless endpoint && endpoint["schemeID"].present? && endpoint.text.present?
    end
  end

  def lines
    rule("BR-16", "an invoice needs at least one line") if @canonical.lines.empty?
    @canonical.lines.each do |line|
      label = "line #{line.id || '?'}"
      rule("BR-21", "#{label} needs an identifier") if line.id.blank?
      rule("BR-22", "#{label} needs a quantity") if line.quantity.nil?
      rule("BR-24", "#{label} needs an amount") if line.amount.nil?
      rule("BR-25", "#{label} needs an item name") if line.name.blank?
      rule("BR-26", "#{label} needs a unit price") if line.unit_price.nil?
      rule("BR-27", "the unit price of #{label} cannot be negative") if line.unit_price&.negative?
      rule("BR-CO-04", "#{label} needs a VAT category") if line.tax_category.blank?
    end
  end

  def vat
    categories = @canonical.lines.map(&:tax_category).compact.uniq
    rule("BR-S-02", "a line at the standard rate needs the VAT number of the seller") if categories.include?("S") && text("/*/AccountingSupplierParty/Party/PartyTaxScheme/CompanyID").nil?
    (@canonical.tax_subtotals.map(&:category) & CATEGORIES_NEEDING_A_REASON).each do |category|
      subtotal = @doc.xpath("/*/TaxTotal/TaxSubtotal").find { |s| s.at_xpath("TaxCategory/ID")&.text == category }
      reason = subtotal && (subtotal.at_xpath("TaxCategory/TaxExemptionReason") || subtotal.at_xpath("TaxCategory/TaxExemptionReasonCode"))
      rule("BR-#{category}-10", "the VAT category #{category} needs an exemption reason") unless reason&.text.present?
    end
  end

  def payment
    payable = @canonical.totals.payable
    return unless @canonical.kind == :invoice && payable&.positive?

    rule("BR-CO-25", "an amount to pay needs a due date or payment terms") if @canonical.due_date.nil? && text("/*/PaymentTerms/Note").nil?
    rule("BR-49", "a payment instruction needs a payment means code") if @doc.at_xpath("/*/PaymentMeans") && text("/*/PaymentMeans/PaymentMeansCode").nil?
  end
end
