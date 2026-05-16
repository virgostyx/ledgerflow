class Peppol::UblInvoiceBuilder
  UBL_NS     = "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
  CAC_NS     = "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
  CBC_NS     = "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
  CUSTOMIZATION_ID = "urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0"
  PROFILE_ID       = "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"

  def initialize(invoice)
    @invoice = invoice
    @partner = invoice.partner
    @lines   = invoice.lines.to_a
    @currency = invoice.currency || "EUR"
  end

  def build
    builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.Invoice("xmlns" => UBL_NS, "xmlns:cac" => CAC_NS, "xmlns:cbc" => CBC_NS) do
        xml["cbc"].CustomizationID CUSTOMIZATION_ID
        xml["cbc"].ProfileID PROFILE_ID
        xml["cbc"].ID @invoice.invoice_number
        xml["cbc"].IssueDate @invoice.invoice_date.to_s
        xml["cbc"].DueDate @invoice.due_date.to_s if @invoice.due_date.present?
        xml["cbc"].InvoiceTypeCode "380"
        xml["cbc"].DocumentCurrencyCode @currency

        build_supplier_party(xml)
        build_customer_party(xml)
        build_tax_total(xml)
        build_monetary_total(xml)
        build_invoice_lines(xml)
      end
    end

    builder.to_xml
  end

  private

  def build_supplier_party(xml)
    xml["cac"].AccountingSupplierParty do
      xml["cac"].Party do
        xml["cac"].PartyName { xml["cbc"].Name PEPPOL_COMPANY_NAME }
        xml["cac"].PostalAddress do
          xml["cac"].Country { xml["cbc"].IdentificationCode PEPPOL_COMPANY_COUNTRY }
        end
        xml["cac"].PartyTaxScheme do
          xml["cbc"].CompanyID PEPPOL_COMPANY_VAT
          xml["cac"].TaxScheme { xml["cbc"].ID "VAT" }
        end
        xml["cac"].PartyLegalEntity do
          xml["cbc"].RegistrationName PEPPOL_COMPANY_NAME
          xml["cbc"].CompanyID PEPPOL_COMPANY_VAT
        end
      end
    end
  end

  def build_customer_party(xml)
    xml["cac"].AccountingCustomerParty do
      xml["cac"].Party do
        xml["cac"].PartyName { xml["cbc"].Name @partner.name }
        xml["cac"].PostalAddress do
          xml["cac"].Country { xml["cbc"].IdentificationCode @partner.country || "BE" }
        end
        if @partner.vat_number.present?
          xml["cac"].PartyTaxScheme do
            xml["cbc"].CompanyID @partner.vat_number
            xml["cac"].TaxScheme { xml["cbc"].ID "VAT" }
          end
        end
        xml["cac"].PartyLegalEntity do
          xml["cbc"].RegistrationName @partner.name
        end
      end
    end
  end

  def build_tax_total(xml)
    xml["cac"].TaxTotal do
      xml["cbc"].TaxAmount(@invoice.vat_amount.to_s, "currencyID" => @currency)

      vat_by_rate.each do |rate, amounts|
        xml["cac"].TaxSubtotal do
          xml["cbc"].TaxableAmount(format("%.2f", amounts[:base]), "currencyID" => @currency)
          xml["cbc"].TaxAmount(format("%.2f", amounts[:vat]), "currencyID" => @currency)
          xml["cac"].TaxCategory do
            xml["cbc"].ID "S"
            xml["cbc"].Percent rate.to_s
            xml["cac"].TaxScheme { xml["cbc"].ID "VAT" }
          end
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
      xml["cac"].InvoiceLine do
        xml["cbc"].ID (index + 1).to_s
        xml["cbc"].InvoicedQuantity(line.quantity.to_s, "unitCode" => "C62")
        xml["cbc"].LineExtensionAmount(format("%.2f", line.subtotal_excl_vat), "currencyID" => @currency)
        xml["cac"].Item do
          xml["cbc"].Name line.description
          xml["cac"].ClassifiedTaxCategory do
            xml["cbc"].ID "S"
            xml["cbc"].Percent line.vat_rate.to_s
            xml["cac"].TaxScheme { xml["cbc"].ID "VAT" }
          end
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
