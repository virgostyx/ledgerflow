# A Peppol invoice or credit note (UBL 2.1, Peppol BIS Billing 3.0) as plain values, whatever the way the XML is laid out. Amounts are BigDecimal,
# dates are Date. Built by Peppol::InvoiceMapper, judged by Peppol::InvoiceChecks, turned into a draft by Peppol::ReceiveInvoice.
Peppol::CanonicalInvoice = Struct.new(:kind, :number, :issue_date, :due_date, :currency, :tax_currency, :supplier, :references, :payment,
                                      :lines, :charges, :tax_subtotals, :totals, :tax_total, keyword_init: true)

# The supplier: names (legal, then trading), VAT number as written, company identifier, endpoint ("scheme:value"), IBAN, address.
Peppol::CanonicalInvoice::Party = Struct.new(:name, :trade_name, :vat, :company_id, :company_scheme, :endpoint, :iban, :street, :city, :zip, :country, keyword_init: true)
Peppol::CanonicalInvoice::Line = Struct.new(:id, :name, :description, :quantity, :unit, :unit_price, :amount, :tax_category, :tax_percent, keyword_init: true)
# A document-level allowance (charge: false) or charge (charge: true).
Peppol::CanonicalInvoice::Charge = Struct.new(:charge, :amount, :reason, :tax_category, :tax_percent, keyword_init: true)
Peppol::CanonicalInvoice::TaxSubtotal = Struct.new(:category, :percent, :taxable, :tax, keyword_init: true)
Peppol::CanonicalInvoice::Totals = Struct.new(:lines, :tax_exclusive, :tax_inclusive, :allowance, :charge, :prepaid, :rounding, :payable, keyword_init: true)
