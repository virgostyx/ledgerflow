# Reads the UBL of an invoice or a credit note (Peppol BIS Billing 3.0) into a Peppol::CanonicalInvoice. Tolerant: what is missing stays nil or
# empty, and Peppol::InvoiceChecks says what is wrong. It refuses only what it cannot read at all (not XML, not an invoice or a credit note).
# Written against the official examples of OpenPeppol, which show what a real document can hold that a first reading did not foresee: several
# TaxTotal (the one in the currency of the document is taken, the other is in the tax currency), negative lines, a supplier with no VAT number,
# a category (O) that has no rate at all (read as 0).
class Peppol::InvoiceMapper
  class Unreadable < StandardError; end

  C = Peppol::CanonicalInvoice

  def self.call(xml) = new(xml).call

  def initialize(xml)
    @doc = Nokogiri::XML(xml.to_s) { |config| config.strict }
    @doc.remove_namespaces!
  rescue Nokogiri::XML::SyntaxError => e
    raise Unreadable, "The document is not well-formed XML: #{e.message.lines.first.to_s.strip}"
  end

  def call
    root = @doc.root
    raise Unreadable, "The document is empty" unless root
    raise Unreadable, "A #{root.name} is not an invoice or a credit note" unless %w[Invoice CreditNote].include?(root.name)

    currency = text("/*/DocumentCurrencyCode")
    tax_total = tax_total_node(currency)
    C.new(kind: root.name == "CreditNote" ? :credit_note : :invoice, number: text("/*/ID"), issue_date: date("/*/IssueDate"), due_date: date("/*/DueDate"),
          currency: currency, tax_currency: text("/*/TaxCurrencyCode"), supplier: supplier, references: references, payment: payment,
          lines: lines, charges: charges, tax_subtotals: tax_subtotals(tax_total), totals: totals, tax_total: amount(tax_total&.at_xpath("TaxAmount")))
  end

  private

  def text(path, node = @doc) = node.at_xpath(path)&.text.to_s.strip.presence

  def date(path)
    Date.iso8601(text(path))
  rescue TypeError, Date::Error
    nil
  end

  def amount(node)
    BigDecimal(node.text.strip) if node && node.text.strip.present?
  rescue ArgumentError
    nil
  end

  def number(path, node = @doc) = amount(node.at_xpath(path))

  def supplier
    party = @doc.at_xpath("/*/AccountingSupplierParty/Party")
    return C::Party.new unless party

    endpoint = party.at_xpath("EndpointID")
    company = party.at_xpath("PartyLegalEntity/CompanyID")
    C::Party.new(name: text("PartyLegalEntity/RegistrationName", party) || text("PartyName/Name", party), trade_name: text("PartyName/Name", party),
                 vat: text("PartyTaxScheme/CompanyID", party), company_id: company&.text&.strip.presence, company_scheme: company && company["schemeID"].presence,
                 endpoint: (endpoint && endpoint["schemeID"].present? && endpoint.text.present? ? "#{endpoint['schemeID']}:#{endpoint.text.strip}" : nil),
                 iban: text("/*/PaymentMeans/PayeeFinancialAccount/ID")&.delete(" ")&.upcase, street: text("PostalAddress/StreetName", party), city: text("PostalAddress/CityName", party),
                 zip: text("PostalAddress/PostalZone", party), country: text("PostalAddress/Country/IdentificationCode", party))
  end

  def references
    { order: text("/*/OrderReference/ID"), buyer: text("/*/BuyerReference"), accounting_cost: text("/*/AccountingCost"),
      billing: text("/*/BillingReference/InvoiceDocumentReference/ID") }.compact
  end

  def payment = { means: text("/*/PaymentMeans/PaymentMeansCode"), id: text("/*/PaymentMeans/PaymentID") }.compact

  def lines
    @doc.xpath("/*/InvoiceLine | /*/CreditNoteLine").map do |line|
      quantity = line.at_xpath("InvoicedQuantity | CreditedQuantity")
      C::Line.new(id: text("ID", line), name: text("Item/Name", line), description: text("Item/Description", line), quantity: amount(quantity), unit: quantity && quantity["unitCode"],
                  unit_price: number("Price/PriceAmount", line), amount: number("LineExtensionAmount", line),
                  tax_category: text("Item/ClassifiedTaxCategory/ID", line), tax_percent: number("Item/ClassifiedTaxCategory/Percent", line) || BigDecimal("0"))
    end
  end

  def charges
    @doc.xpath("/*/AllowanceCharge").map do |node|
      C::Charge.new(charge: text("ChargeIndicator", node) == "true", amount: number("Amount", node) || BigDecimal("0"), reason: text("AllowanceChargeReason", node),
                    tax_category: text("TaxCategory/ID", node), tax_percent: number("TaxCategory/Percent", node) || BigDecimal("0"))
    end
  end

  # Several TaxTotal when the document also gives the VAT in a tax currency: the one in the currency of the document counts.
  def tax_total_node(currency)
    nodes = @doc.xpath("/*/TaxTotal")
    nodes.find { |n| n.at_xpath("TaxAmount")&.[]("currencyID") == currency } || nodes.first
  end

  def tax_subtotals(tax_total)
    return [] unless tax_total

    tax_total.xpath("TaxSubtotal").map do |node|
      C::TaxSubtotal.new(category: text("TaxCategory/ID", node), percent: number("TaxCategory/Percent", node) || BigDecimal("0"), taxable: number("TaxableAmount", node), tax: number("TaxAmount", node))
    end
  end

  def totals
    base = "/*/LegalMonetaryTotal"
    C::Totals.new(lines: number("#{base}/LineExtensionAmount"), tax_exclusive: number("#{base}/TaxExclusiveAmount"), tax_inclusive: number("#{base}/TaxInclusiveAmount"),
                  allowance: number("#{base}/AllowanceTotalAmount"), charge: number("#{base}/ChargeTotalAmount"), prepaid: number("#{base}/PrepaidAmount"),
                  rounding: number("#{base}/PayableRoundingAmount"), payable: number("#{base}/PayableAmount"))
  end
end
