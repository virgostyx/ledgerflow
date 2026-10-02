# An invoice or credit note in UBL (Peppol BIS Billing 3.0), read straight from the XML: nothing is guessed, each field
# says which element it came from. An XML that declares entities is refused, and no entity is ever resolved.
class Accounting::Extractors::Ubl
  def self.call(xml) = new(xml).call

  def initialize(xml)
    raise Accounting::Extractors::Unreadable, "unsafe XML" if xml.to_s.match?(/<!DOCTYPE|<!ENTITY/i)

    @doc = Nokogiri::XML(xml.to_s) { |config| config.strict.nonet }
    @doc.remove_namespaces!
    raise Accounting::Extractors::Unreadable, "not an invoice" unless %w[Invoice CreditNote].include?(@doc.root&.name)
  rescue Nokogiri::XML::SyntaxError
    raise Accounting::Extractors::Unreadable, "damaged XML"
  end

  def call
    fields = {}
    put(fields, :invoice_number, "/*/ID")
    put(fields, :invoice_date, "/*/IssueDate")
    put(fields, :due_date, "/*/DueDate")
    put(fields, :currency, "/*/DocumentCurrencyCode")
    put(fields, :supplier_name, "//AccountingSupplierParty//PartyName/Name") || put(fields, :supplier_name, "//AccountingSupplierParty//PartyLegalEntity/RegistrationName")
    put(fields, :subtotal, "//LegalMonetaryTotal/TaxExclusiveAmount") { |v| amount(v) }
    put(fields, :total, "//LegalMonetaryTotal/TaxInclusiveAmount") { |v| amount(v) } || put(fields, :total, "//LegalMonetaryTotal/PayableAmount") { |v| amount(v) }
    put(fields, :vat_amount, "//TaxTotal/TaxAmount") { |v| amount(v) }
    put(fields, :supplier_vat, "//AccountingSupplierParty//PartyTaxScheme/CompanyID") { |v| vat(v) }
    put(fields, :iban, "//PaymentMeans/PayeeFinancialAccount/ID") { |v| Accounting::Iban.normalize(v) if Accounting::Iban.valid?(v) }
    put(fields, :structured_communication, "//PaymentMeans/PaymentID") { |v| communication(v) }
    fields[:document_type] = { value: @doc.root.name == "CreditNote" ? "credit_note" : "invoice", snippet: "/#{@doc.root.name}", page: nil, confidence: :high }
    fields.merge!(Accounting::DocumentFieldParser.partner_fields(fields[:supplier_vat]))
    Accounting::Extractors::Result.new(text: text, method: "ubl", confidence: 100, fields: fields)
  end

  private

  # Adds the field when the element exists and (after the optional cleaning block) holds a value.
  def put(fields, name, xpath)
    node = @doc.at_xpath(xpath)
    return unless node

    value = block_given? ? yield(node.text.strip) : node.text.strip
    return if value.blank?

    fields[name] = { value: value, snippet: "#{node.path}: #{node.text.strip}", page: nil, confidence: :high }
    true
  end

  def amount(text)
    format("%.2f", BigDecimal(text))
  rescue ArgumentError
    nil
  end

  def vat(text)
    number = text.upcase.gsub(/[\s.]/, "")
    number if !number.start_with?("BE") || Accounting::BelgianVatNumber.valid?(number)
  end

  def communication(text)
    digits = Accounting::StructuredCommunication.extract(text)
    "+++#{digits[0, 3]}/#{digits[3, 4]}/#{digits[7, 5]}+++" if digits
  end

  def text = @doc.xpath("//text()").map { |node| node.text.strip }.reject(&:empty?).join("\n")
end
