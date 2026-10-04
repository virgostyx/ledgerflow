# A valid, consistent Peppol BIS Billing 3.0 invoice or credit note for the specs of the reception (F06), built from a few choices: the
# supplier (Belgian VAT BE0123456749, a valid one), the number, the lines [[net amount, category, percent]], a document-level charge.
module PeppolUbl
  SUPPLIER_VAT = "BE0123456749".freeze

  def self.invoice(number: "SUP-2026-001", root: "Invoice", vat: SUPPLIER_VAT, name: "Fournisseur SA", lines: [ [ 100, "S", 21 ] ], charge: nil, currency: "EUR",
                   issue: "2026-09-01", due: "2026-10-01", extra: "", iban: nil, payment_id: nil, country: "BE")
    charge_xml = charge ? allowance_charge(charge, true, lines.first) : ""
    groups = lines.group_by { |_, cat, pct| [ cat, pct ] }.map do |(cat, pct), rows|
      taxable = rows.sum { |net, _, _| net } + (charge && [ lines.first[1], lines.first[2] ] == [ cat, pct ] ? charge : 0)
      [ cat, pct, taxable, (taxable * pct / 100.0).round(2) ]
    end
    net_lines = lines.sum { |net, _, _| net }
    exclusive = net_lines + (charge || 0)
    tax = groups.sum { |g| g[3] }
    line_tag = root == "CreditNote" ? "CreditNoteLine" : "InvoiceLine"
    qty_tag = root == "CreditNote" ? "CreditedQuantity" : "InvoicedQuantity"
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <#{root} xmlns="urn:oasis:names:specification:ubl:schema:xsd:#{root}-2"
               xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
               xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        <cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0</cbc:CustomizationID>
        <cbc:ProfileID>urn:fdc:peppol.eu:2017:poacc:billing:01:1.0</cbc:ProfileID>
        <cbc:ID>#{number}</cbc:ID>
        <cbc:IssueDate>#{issue}</cbc:IssueDate>
        #{"<cbc:DueDate>#{due}</cbc:DueDate>" if due}
        <cbc:#{root == 'CreditNote' ? 'CreditNoteTypeCode' : 'InvoiceTypeCode'}>#{root == 'CreditNote' ? 381 : 380}</cbc:#{root == 'CreditNote' ? 'CreditNoteTypeCode' : 'InvoiceTypeCode'}>
        <cbc:DocumentCurrencyCode>#{currency}</cbc:DocumentCurrencyCode>
        #{extra}
        <cac:AccountingSupplierParty><cac:Party>
          <cbc:EndpointID schemeID="0208">#{vat.to_s.sub(/\A[A-Z]{2}/, '')}</cbc:EndpointID>
          <cac:PartyName><cbc:Name>#{name}</cbc:Name></cac:PartyName>
          <cac:PostalAddress><cbc:StreetName>Rue 1</cbc:StreetName><cbc:CityName>Bruxelles</cbc:CityName><cbc:PostalZone>1000</cbc:PostalZone><cac:Country><cbc:IdentificationCode>#{country}</cbc:IdentificationCode></cac:Country></cac:PostalAddress>
          #{"<cac:PartyTaxScheme><cbc:CompanyID>#{vat}</cbc:CompanyID><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme>" if vat}
          <cac:PartyLegalEntity><cbc:RegistrationName>#{name}</cbc:RegistrationName></cac:PartyLegalEntity>
        </cac:Party></cac:AccountingSupplierParty>
        #{"<cac:PaymentMeans><cbc:PaymentMeansCode>30</cbc:PaymentMeansCode>#{"<cbc:PaymentID>#{payment_id}</cbc:PaymentID>" if payment_id}#{"<cac:PayeeFinancialAccount><cbc:ID>#{iban}</cbc:ID></cac:PayeeFinancialAccount>" if iban}</cac:PaymentMeans>" if iban || payment_id}
        #{charge_xml}
        <cac:TaxTotal><cbc:TaxAmount currencyID="#{currency}">#{format('%.2f', tax)}</cbc:TaxAmount>
          #{groups.map { |cat, pct, taxable, amount| "<cac:TaxSubtotal><cbc:TaxableAmount currencyID=\"#{currency}\">#{format('%.2f', taxable)}</cbc:TaxableAmount><cbc:TaxAmount currencyID=\"#{currency}\">#{format('%.2f', amount)}</cbc:TaxAmount><cac:TaxCategory><cbc:ID>#{cat}</cbc:ID><cbc:Percent>#{pct}</cbc:Percent><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:TaxCategory></cac:TaxSubtotal>" }.join}
        </cac:TaxTotal>
        <cac:LegalMonetaryTotal>
          <cbc:LineExtensionAmount currencyID="#{currency}">#{format('%.2f', net_lines)}</cbc:LineExtensionAmount>
          <cbc:TaxExclusiveAmount currencyID="#{currency}">#{format('%.2f', exclusive)}</cbc:TaxExclusiveAmount>
          <cbc:TaxInclusiveAmount currencyID="#{currency}">#{format('%.2f', exclusive + tax)}</cbc:TaxInclusiveAmount>
          #{"<cbc:ChargeTotalAmount currencyID=\"#{currency}\">#{format('%.2f', charge)}</cbc:ChargeTotalAmount>" if charge}
          <cbc:PayableAmount currencyID="#{currency}">#{format('%.2f', exclusive + tax)}</cbc:PayableAmount>
        </cac:LegalMonetaryTotal>
        #{lines.each_with_index.map { |(net, cat, pct), i| "<cac:#{line_tag}><cbc:ID>#{i + 1}</cbc:ID><cbc:#{qty_tag} unitCode=\"C62\">1</cbc:#{qty_tag}><cbc:LineExtensionAmount currencyID=\"#{currency}\">#{format('%.2f', net)}</cbc:LineExtensionAmount><cac:Item><cbc:Name>Item #{i + 1}</cbc:Name><cac:ClassifiedTaxCategory><cbc:ID>#{cat}</cbc:ID><cbc:Percent>#{pct}</cbc:Percent><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:ClassifiedTaxCategory></cac:Item><cac:Price><cbc:PriceAmount currencyID=\"#{currency}\">#{format('%.2f', net)}</cbc:PriceAmount></cac:Price></cac:#{line_tag}>" }.join}
      </#{root}>
    XML
  end

  def self.allowance_charge(amount, charge, line)
    "<cac:AllowanceCharge><cbc:ChargeIndicator>#{charge}</cbc:ChargeIndicator><cbc:AllowanceChargeReason>Insurance</cbc:AllowanceChargeReason>" \
      "<cbc:Amount currencyID=\"EUR\">#{format('%.2f', amount)}</cbc:Amount><cac:TaxCategory><cbc:ID>#{line[1]}</cbc:ID><cbc:Percent>#{line[2]}</cbc:Percent>" \
      "<cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:TaxCategory></cac:AllowanceCharge>"
  end
end
