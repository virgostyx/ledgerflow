# A UBL invoice received through Peppol becomes a draft supplier invoice that keeps what was received: the original XML,
# the PDF the supplier embedded in it (EmbeddedDocumentBinaryObject), the order reference (OrderReference/ID) and the buyer
# reference (BuyerReference). All or nothing. An Access Point may deliver the same document twice: the invoice already
# received (same supplier, same number, not cancelled) is returned instead of a second draft.
class Peppol::ReceiveInvoice
  # ponytail: no scan or size policy beyond this; a larger embedded file is simply not kept (the XML still is).
  PDF_MAX_BYTES = 15.megabytes

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

    invoice = nil
    ApplicationRecord.transaction(requires_new: true) do
      partner = Accounting::Partner.find_by(vat_number: supplier_vat)
      partner ||= Accounting::Partner.create!(
        name: doc.at_xpath("//AccountingSupplierParty//PartyName/Name")&.text || supplier_vat,
        partner_type: :supplier,
        vat_number:   supplier_vat,
        country:      "BE"
      )

      invoice = already_received(partner, invoice_number) || Accounting::Invoice.create!(
        invoice_type:    :supplier,
        document_type:   doc.root.name == "CreditNote" ? :credit_note : :invoice,
        invoice_date:    Date.parse(issue_date),
        due_date:        due_date.present? ? Date.parse(due_date) : nil,
        currency:        currency,
        external_ref:    invoice_number,
        order_reference: text_of(doc.at_xpath("//OrderReference/ID")),
        buyer_reference: text_of(doc.at_xpath("/*/BuyerReference")),
        subtotal_excl_vat: subtotal.present? ? BigDecimal(subtotal) : BigDecimal("0"),
        vat_amount:      vat_amount.present? ? BigDecimal(vat_amount) : BigDecimal("0"),
        total_incl_vat:  BigDecimal(total_incl),
        partner:         partner,
        fiscal_year:     fiscal_year,
        status:          :draft
      ).tap { |created| keep_documents(created, xml, doc, invoice_number) }
    end

    LightService::Context.make(invoice: invoice)
  rescue StandardError => e
    ctx = LightService::Context.make
    ctx.fail!("Receive error: #{e.message}")
    ctx
  end

  def self.validate_required!(*values)
    raise ArgumentError, "Missing required UBL fields" if values.any?(&:blank?)
  end

  def self.already_received(partner, invoice_number)
    Accounting::Invoice.supplier.where(partner: partner, external_ref: invoice_number).where.not(status: :cancelled).first
  end

  def self.text_of(node) = node&.text.to_s.strip.presence

  # The XML as received is the original; the PDF is only a representation, when the supplier embedded one.
  def self.keep_documents(invoice, xml, doc, invoice_number)
    invoice.ubl_document.attach(io: StringIO.new(xml), filename: "#{file_name(invoice_number)}.xml", content_type: "application/xml")
    pdf = embedded_pdf(doc, invoice_number)
    invoice.pdf_document.attach(**pdf) if pdf
  end

  # The first embedded file that really is a PDF (declared as one, starts with %PDF, within the size limit).
  def self.embedded_pdf(doc, invoice_number)
    doc.xpath("//AdditionalDocumentReference/Attachment/EmbeddedDocumentBinaryObject").each do |node|
      next unless node["mimeCode"].to_s.casecmp?("application/pdf")

      bytes = Base64.decode64(node.text.to_s)
      next unless bytes.start_with?("%PDF") && bytes.bytesize <= PDF_MAX_BYTES

      return { io: StringIO.new(bytes), filename: file_name(node["filename"].presence || "#{invoice_number}.pdf"), content_type: "application/pdf" }
    end
    nil
  end

  def self.file_name(name) = name.to_s.gsub(/[^\w.\-]+/, "_")
  private_class_method :validate_required!, :already_received, :text_of, :keep_documents, :embedded_pdf, :file_name
end
