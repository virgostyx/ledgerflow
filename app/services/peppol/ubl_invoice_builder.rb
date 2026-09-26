class Peppol::UblInvoiceBuilder
  UBL_NS     = "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
  CREDIT_NOTE_NS = "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2"
  CAC_NS     = "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
  CBC_NS     = "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
  CUSTOMIZATION_ID = "urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0"
  PROFILE_ID       = "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"

  # Same wording as the PDF; a franchise exemption has its own reason. Anything else is standard rate (S), or zero rate (Z).
  EXEMPTION_CATEGORIES = {
    "intracom_goods" => "K", "intracom_services" => "AE", "construction_reverse_charge" => "AE", "export" => "G", "exempt" => "E"
  }.freeze

  # ponytail: conformity with the official BIS 3.0 rules (Schematron) is not checked offline; see the handoff.
  def initialize(invoice)
    @invoice = invoice
    @entity  = invoice.entity
    @partner = invoice.partner
    @lines   = invoice.lines.to_a
    @currency = invoice.currency || "EUR"
    @credit_note = invoice.credit_note?
  end

  def build
    builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.send(@credit_note ? "CreditNote" : "Invoice",
               "xmlns" => @credit_note ? CREDIT_NOTE_NS : UBL_NS, "xmlns:cac" => CAC_NS, "xmlns:cbc" => CBC_NS) do
        xml["cbc"].CustomizationID CUSTOMIZATION_ID
        xml["cbc"].ProfileID PROFILE_ID
        xml["cbc"].ID @invoice.invoice_number
        xml["cbc"].IssueDate @invoice.invoice_date.to_s
        xml["cbc"].DueDate @invoice.due_date.to_s if @invoice.due_date.present? && !@credit_note
        if @credit_note
          xml["cbc"].CreditNoteTypeCode "381"
        else
          xml["cbc"].InvoiceTypeCode "380"
        end
        xml["cbc"].DocumentCurrencyCode @currency
        xml["cbc"].BuyerReference(@invoice.external_ref.presence || @invoice.invoice_number)
        build_billing_reference(xml)

        build_supplier_party(xml)
        build_customer_party(xml)
        build_payment_means(xml)
        build_tax_total(xml)
        build_monetary_total(xml)
        build_invoice_lines(xml)
      end
    end

    builder.to_xml
  end

  private

  def build_billing_reference(xml)
    return unless @credit_note && @invoice.credited_invoice&.invoice_number

    xml["cac"].BillingReference do
      xml["cac"].InvoiceDocumentReference { xml["cbc"].ID @invoice.credited_invoice.invoice_number }
    end
  end

  def build_supplier_party(xml)
    xml["cac"].AccountingSupplierParty do
      xml["cac"].Party do
        build_endpoint(xml, @entity.peppol_participant_id)
        xml["cac"].PartyName { xml["cbc"].Name @entity.name }
        build_address(xml, @entity.address_line1, @entity.city, @entity.zip_code, @entity.country)
        if @entity.vat_number.present?
          xml["cac"].PartyTaxScheme do
            xml["cbc"].CompanyID @entity.vat_number
            xml["cac"].TaxScheme { xml["cbc"].ID "VAT" }
          end
        end
        xml["cac"].PartyLegalEntity do
          xml["cbc"].RegistrationName @entity.legal_name
          scheme, number = @entity.peppol_participant_id.to_s.split(":", 2)
          xml["cbc"].CompanyID(number, "schemeID" => scheme) if scheme == Peppol::ParticipantId::BELGIAN_SCHEME
        end
      end
    end
  end

  def build_customer_party(xml)
    xml["cac"].AccountingCustomerParty do
      xml["cac"].Party do
        build_endpoint(xml, @partner.peppol_participant_id_or_default)
        xml["cac"].PartyName { xml["cbc"].Name @partner.name }
        build_address(xml, @partner.street, @partner.city, @partner.zip, @partner.country || "BE")
        if @partner.vat_number.present?
          xml["cac"].PartyTaxScheme do
            xml["cbc"].CompanyID @partner.vat_number
            xml["cac"].TaxScheme { xml["cbc"].ID "VAT" }
          end
        end
        xml["cac"].PartyLegalEntity do
          xml["cbc"].RegistrationName @partner.name
        end
        xml["cac"].Contact { xml["cbc"].ElectronicMail @partner.email } if @partner.email.present?
      end
    end
  end

  def build_endpoint(xml, participant_id)
    return if participant_id.blank?

    scheme, value = participant_id.split(":", 2)
    xml["cbc"].EndpointID(value, "schemeID" => scheme)
  end

  def build_address(xml, street, city, zip, country)
    xml["cac"].PostalAddress do
      xml["cbc"].StreetName street if street.present?
      xml["cbc"].CityName city if city.present?
      xml["cbc"].PostalZone zip if zip.present?
      xml["cac"].Country { xml["cbc"].IdentificationCode country }
    end
  end

  # Credit transfer (30) to the first active bank account, like the PDF.
  def build_payment_means(xml)
    bank = Accounting::BankAccount.active.order(:id).first
    return unless bank

    xml["cac"].PaymentMeans do
      xml["cbc"].PaymentMeansCode "30"
      xml["cac"].PayeeFinancialAccount { xml["cbc"].ID bank.iban }
    end
  end

  # [category code, exemption reason or nil] for a rate.
  def tax_category(rate)
    return [ "E", Accounting::InvoicePdf::FRANCHISE_MENTION ] if @entity.franchise?

    code = EXEMPTION_CATEGORIES[@invoice.vat_treatment]
    return [ code, Accounting::InvoicePdf::LEGAL_MENTIONS.fetch(@invoice.vat_treatment) ] if code

    [ rate.zero? ? "Z" : "S", nil ]
  end

  def build_tax_category(xml, rate, tag: "TaxCategory")
    code, reason = tax_category(rate)
    xml["cac"].send(tag) do
      xml["cbc"].ID code
      xml["cbc"].Percent rate.to_s
      xml["cbc"].TaxExemptionReason reason if reason && tag == "TaxCategory"
      xml["cac"].TaxScheme { xml["cbc"].ID "VAT" }
    end
  end

  def build_tax_total(xml)
    xml["cac"].TaxTotal do
      xml["cbc"].TaxAmount(@invoice.vat_amount.to_s, "currencyID" => @currency)

      vat_by_rate.each do |rate, amounts|
        xml["cac"].TaxSubtotal do
          xml["cbc"].TaxableAmount(format("%.2f", amounts[:base]), "currencyID" => @currency)
          xml["cbc"].TaxAmount(format("%.2f", amounts[:vat]), "currencyID" => @currency)
          build_tax_category(xml, rate)
        end
      end
    end
  end

  def build_monetary_total(xml)
    xml["cac"].LegalMonetaryTotal do
      xml["cbc"].LineExtensionAmount(format("%.2f", @invoice.subtotal_excl_vat), "currencyID" => @currency)
      xml["cbc"].TaxExclusiveAmount(format("%.2f", @invoice.subtotal_excl_vat), "currencyID" => @currency)
      xml["cbc"].TaxInclusiveAmount(format("%.2f", @invoice.total_incl_vat), "currencyID" => @currency)
      xml["cbc"].PayableAmount(format("%.2f", @invoice.total_incl_vat), "currencyID" => @currency)
    end
  end

  def build_invoice_lines(xml)
    @lines.each_with_index do |line, index|
      xml["cac"].send(@credit_note ? "CreditNoteLine" : "InvoiceLine") do
        xml["cbc"].ID (index + 1).to_s
        xml["cbc"].send(@credit_note ? "CreditedQuantity" : "InvoicedQuantity", line.quantity.to_s, "unitCode" => "C62")
        xml["cbc"].LineExtensionAmount(format("%.2f", line.subtotal_excl_vat), "currencyID" => @currency)
        xml["cac"].Item do
          xml["cbc"].Name line.description
          build_tax_category(xml, line.vat_rate.to_i, tag: "ClassifiedTaxCategory")
        end
        xml["cac"].Price do
          xml["cbc"].PriceAmount(format("%.2f", line.unit_price), "currencyID" => @currency)
        end
      end
    end
  end

  def vat_by_rate
    @lines.each_with_object({}) do |line, acc|
      rate = line.vat_rate.to_i
      acc[rate] ||= { base: BigDecimal("0"), vat: BigDecimal("0") }
      acc[rate][:base] += line.subtotal_excl_vat
      acc[rate][:vat]  += line.vat_amount
    end
  end
end
