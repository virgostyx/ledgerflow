# Invoice whose VAT differs from Σ line base × rate by more than 5 cents (rounding per line).
class Accounting::Consistency::Checks::C09VatBaseRate < Accounting::Consistency::Check
  self.check_id = "C09"
  self.severity = "warning"
  self.title = "Base × rate inconsistent with the VAT"
  TOLERANCE = "0.05".freeze

  def call
    Accounting::Invoice.joins(:lines).where.not(status: [ Accounting::Invoice.statuses[:draft], Accounting::Invoice.statuses[:cancelled] ])
      .group("accounting_invoices.id", "accounting_invoices.invoice_number", "accounting_invoices.vat_amount")
      .having("ABS(SUM(ROUND(accounting_invoice_lines.subtotal_excl_vat * accounting_invoice_lines.vat_rate / 100, 2)) - accounting_invoices.vat_amount) > #{TOLERANCE}")
      .pluck(Arel.sql("accounting_invoices.id"), Arel.sql("accounting_invoices.invoice_number"), Arel.sql("accounting_invoices.vat_amount"),
             Arel.sql("SUM(ROUND(accounting_invoice_lines.subtotal_excl_vat * accounting_invoice_lines.vat_rate / 100, 2))")).map do |id, number, booked, expected|
      finding(subject: [ "Accounting::Invoice", id ], message: "Invoice #{number || "##{id}"}: VAT #{booked}, base × rate gives #{expected}", booked: booked, expected: expected)
    end
  end
end
