# What an approver wants to know of the supplier at a glance (B01a §4.3): the five latest posted invoices (same currency) and
# their average, and a warning when this invoice is worth more than twice that average (at least three invoices behind it).
# An invoice with a warning is never taken in a bulk approval.
# ponytail: duplicate (F03), IBAN change (B01b) and budget (R11) warnings join `warnings` when those exist for invoices.
class Approvals::SupplierHistory
  Result = Struct.new(:recent, :average, :amount, :unusual_amount, keyword_init: true) do
    alias_method :unusual_amount?, :unusual_amount
    def warnings = [ (:unusual_amount if unusual_amount) ].compact
  end

  RECENT = 5
  MIN_FOR_AVERAGE = 3
  TOLERANCE = 2

  def self.for(invoice)
    latest = Accounting::Invoice.supplier.invoice.where(partner_id: invoice.partner_id, currency: invoice.currency, status: %i[posted partially_paid paid])
                                .where.not(id: invoice.id).order(invoice_date: :desc, id: :desc).limit(RECENT)
    recent = latest.to_a
    average = Accounting::Invoice.where(id: recent.map(&:id)).average(:total_incl_vat)&.round(2) if recent.any? # the database adds up
    amount = invoice.lines.sum(:total_incl_vat)
    Result.new(recent: recent, average: average, amount: amount,
               unusual_amount: recent.size >= MIN_FOR_AVERAGE && amount > TOLERANCE * average)
  end
end
