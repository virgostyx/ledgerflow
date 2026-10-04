# A UBL invoice received through Peppol becomes a draft supplier invoice that keeps what was received: the original XML,
# the PDF the supplier embedded in it (EmbeddedDocumentBinaryObject), the order reference (OrderReference/ID) and the buyer
# reference (BuyerReference). All or nothing. An Access Point may deliver the same document twice: the invoice already
# received (same supplier, same number, not cancelled) is returned instead of a second draft.
class Peppol::ReceiveInvoice
  # `exchange_rate`: the rate of a document that is not in euros (never guessed: Peppol::ProcessMessage finds it, or the message waits).
  # => ctx[:invoice], ctx[:duplicate] (an invoice with the same supplier and number was already there: it is returned, no second draft)
  # `plan`: Peppol::InvoicePlan::Plan, the lines, treatment, journal and references of the draft (without one, only the header and the amounts).
  # `partner`: the supplier when Peppol::SupplierMatch found it; nil: it is created, as a supplier "to validate".
  def self.call(xml:, fiscal_year:, exchange_rate: nil, plan: nil, partner: nil)
    canonical = Peppol::InvoiceMapper.call(xml)
    totals = canonical.totals
    validate_required!(canonical.number, canonical.issue_date, totals.tax_inclusive)
    raise ArgumentError, "The exchange rate of #{canonical.currency} is needed" if canonical.currency != "EUR" && exchange_rate.blank?

    invoice = nil
    duplicate = false
    ApplicationRecord.transaction(requires_new: true) do
      partner ||= supplier_partner(canonical.supplier)
      invoice = already_received(partner, canonical.number)
      duplicate = invoice.present?
      invoice ||= Accounting::Invoice.create!(
        invoice_type:    :supplier,
        document_type:   canonical.kind == :credit_note ? :credit_note : :invoice,
        invoice_date:    canonical.issue_date,
        due_date:        canonical.due_date,
        currency:        canonical.currency,
        exchange_rate:   exchange_rate || 1,
        external_ref:    canonical.number,
        supplier_reference: canonical.number,
        order_reference: canonical.references[:order],
        buyer_reference: canonical.references[:buyer],
        subtotal_excl_vat: totals.tax_exclusive || BigDecimal("0"),
        vat_amount:      canonical.tax_total || BigDecimal("0"),
        total_incl_vat:  totals.tax_inclusive,
        partner:         partner,
        fiscal_year:     fiscal_year,
        status:          :draft,
        **plan_attributes(plan)
      ).tap do |created|
        add_lines(created, plan) if plan
        keep_documents(created, xml, Nokogiri::XML(xml).tap(&:remove_namespaces!), canonical.number)
        announce(created)
      end
    end

    LightService::Context.make(invoice: invoice, duplicate: duplicate)
  rescue StandardError => e
    ctx = LightService::Context.make
    ctx.fail!("Receive error: #{e.message}")
    ctx
  end

  # The treatment, journal, payment reference and credited invoice the plan decided.
  def self.plan_attributes(plan)
    return {} unless plan

    { vat_treatment: plan.treatment, journal: plan.journal, payment_reference: plan.payment_reference.presence, credited_invoice: plan.credited_invoice }.compact
  end

  # One line per planned group; the totals are then those of the lines, which is what will be posted (the VAT recomputed by category is within
  # a cent of the document's: the checks made sure of it).
  def self.add_lines(invoice, plan)
    plan.lines.each_with_index do |line, i|
      invoice.lines.create!(description: line.description, account: line.account, quantity: 1, unit_price: line.amount, vat_rate: line.vat_rate, position: i + 1)
    end
    invoice.lines.reload
    invoice.compute_totals
    invoice.save!
  end

  # The supplier already known by its VAT number (or, with none, by its exact name), else a new one, with the country and the address of the
  # document. A VAT number that is not an EU one is not kept (the partner would be refused): the supplier is still created.
  def self.supplier_partner(supplier)
    vat = supplier.vat.presence
    found = vat && Accounting::Partner.find_by(vat_number: vat)
    found ||= Accounting::Partner.supplier.find_by("lower(name) = ?", supplier.name.to_s.downcase) if vat.nil? && supplier.name.present?
    found || Accounting::Partner.create!(
      name: supplier.name.presence || vat || "Unknown supplier", partner_type: :supplier, country: supplier.country.presence || "BE",
      vat_number: (vat if vat && Accounting::Partner.valid_vat_number?(vat)), street: supplier.street, city: supplier.city, zip: supplier.zip,
      iban: (Accounting::Iban.normalize(supplier.iban) if Accounting::Iban.valid?(supplier.iban)), to_validate: true
    )
  end

  def self.validate_required!(*values)
    raise ArgumentError, "Missing required UBL fields" if values.any?(&:blank?)
  end

  # By the supplier's number: external_ref may since have been taken over by a third party (an invoice received before
  # supplier_reference existed still carries the number there).
  def self.already_received(partner, invoice_number)
    Accounting::Invoice.supplier.where(partner: partner).where.not(status: :cancelled)
                       .where("supplier_reference = :n OR (supplier_reference IS NULL AND external_ref = :n)", n: invoice_number).first
  end

  # An entity that uses BudgetFlow tells it about the invoice (credit notes are not handled there yet).
  def self.announce(invoice)
    Accounting::InvoiceEvent.record_received!(invoice) if ActsAsTenant.current_tenant&.budgetflow? && invoice.invoice?
  end

  def self.text_of(node) = node&.text.to_s.strip.presence

  # The XML as received is the original; the PDF is only a representation, when the supplier embedded one.
  def self.keep_documents(invoice, xml, doc, invoice_number)
    invoice.ubl_document.attach(io: StringIO.new(xml), filename: "#{file_name(invoice_number)}.xml", content_type: "application/xml")
    pdf = embedded_pdf(doc, invoice_number)
    invoice.pdf_document.attach(**pdf) if pdf
  end

  # The PDF the supplier embedded, if any (Peppol::EmbeddedPdf).
  def self.embedded_pdf(doc, invoice_number)
    pdf = Peppol::EmbeddedPdf.find(doc) or return
    { io: StringIO.new(pdf[:bytes]), filename: file_name(pdf[:filename].presence || "#{invoice_number}.pdf"), content_type: "application/pdf" }
  end

  def self.file_name(name) = name.to_s.gsub(/[^\w.\-]+/, "_")
  private_class_method :validate_required!, :already_received, :announce, :text_of, :keep_documents, :embedded_pdf, :file_name, :supplier_partner, :plan_attributes, :add_lines
end
