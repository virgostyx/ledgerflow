class Peppol::ReceiveInvoice
  def self.call(xml:, fiscal_year:)
    doc = Nokogiri::XML(xml)
    doc.remove_namespaces!

    invoice_number = doc.at_xpath("//ID")&.text
    issue_date     = doc.at_xpath("//IssueDate")&.text
    due_date       = doc.at_xpath("//DueDate")&.text
    currency       = doc.at_xpath("//DocumentCurrencyCode")&.text || "EUR"
    supplier_vat   = doc.at_xpath("//AccountingSupplierParty//CompanyID")&.text
    subtotal       = doc.at_xpath("//LegalMonetaryTotal/TaxExclusiveAmount")&.text
    total_incl     = doc.at_xpath("//LegalMonetaryTotal/TaxInclusiveAmount")&.text
    vat_amount     = doc.at_xpath("//TaxTotal/TaxAmount")&.text

    validate_required!(invoice_number, issue_date, total_incl)

    partner = Accounting::Partner.find_by(vat_number: supplier_vat)
    partner ||= Accounting::Partner.create!(
      name: doc.at_xpath("//AccountingSupplierParty//PartyName/Name")&.text || supplier_vat,
      partner_type: :supplier,
      vat_number:   supplier_vat,
      country:      "BE"
    )

    invoice = Accounting::Invoice.create!(
      invoice_type:    :supplier,
      invoice_date:    Date.parse(issue_date),
      due_date:        due_date.present? ? Date.parse(due_date) : nil,
      currency:        currency,
      external_ref:    invoice_number,
      subtotal_excl_vat: subtotal.present? ? BigDecimal(subtotal) : BigDecimal("0"),
      vat_amount:      vat_amount.present? ? BigDecimal(vat_amount) : BigDecimal("0"),
      total_incl_vat:  BigDecimal(total_incl),
      partner:         partner,
      fiscal_year:     fiscal_year,
      status:          :draft
    )

    ctx = LightService::Context.make(invoice: invoice)
    ctx
  rescue StandardError => e
    ctx = LightService::Context.make
    ctx.fail!("Receive error: #{e.message}")
    ctx
  end

  def self.validate_required!(*values)
    raise ArgumentError, "Missing required UBL fields" if values.any?(&:blank?)
  end
  private_class_method :validate_required!
end
