# What an approver wants to know of the supplier at a glance (B01a §4.3): the five latest posted invoices (same currency) and
# their average, and a warning when this invoice is worth more than twice that average (at least three invoices behind it).
# An invoice with a warning is never taken in a bulk approval. `for_many` answers for a whole list in two queries (the screens and the
# summary read many at once); `for` is the same thing for one.
# ponytail: duplicate (F03), IBAN change (B01b) and budget (R11) warnings join `warnings` when those exist for invoices.
class Approvals::SupplierHistory
  Result = Struct.new(:recent, :average, :amount, :unusual_amount, keyword_init: true) do
    alias_method :unusual_amount?, :unusual_amount
    def warnings = [ (:unusual_amount if unusual_amount) ].compact
  end

  RECENT = 5
  MIN_FOR_AVERAGE = 3
  TOLERANCE = 2

  def self.for(invoice) = for_many([ invoice ]).fetch(invoice.id)

  # => { invoice_id => Result }. `amounts`: { invoice_id => sum of the lines incl. VAT, in the currency of the invoice }, added up by the database when not given.
  def self.for_many(invoices, amounts: nil)
    amounts ||= Accounting::InvoiceLine.unscope(:order).where(invoice_id: invoices.map(&:id)).group(:invoice_id).sum(:total_incl_vat)
    past = latest_by_supplier(invoices)
    invoices.to_h do |invoice|
      recent = past.fetch([ invoice.partner_id, invoice.currency ], []).reject { |other| other.id == invoice.id }.first(RECENT)
      average = (recent.sum(&:total_incl_vat) / recent.size).round(2) if recent.any?
      amount = amounts.fetch(invoice.id, 0)
      [ invoice.id, Result.new(recent: recent, average: average, amount: amount, unusual_amount: recent.size >= MIN_FOR_AVERAGE && amount > TOLERANCE * average) ]
    end
  end

  # The latest posted invoices of each (supplier, currency), newest first; one more than needed, since the invoice asked about may be one of them.
  def self.latest_by_supplier(invoices)
    return {} if invoices.empty?

    ranked = Accounting::Invoice.supplier.invoice.where(status: %i[posted partially_paid paid], partner_id: invoices.map(&:partner_id).uniq, currency: invoices.map(&:currency).uniq)
                                .select("accounting_invoices.*, ROW_NUMBER() OVER (PARTITION BY partner_id, currency ORDER BY invoice_date DESC, id DESC) AS history_rank")
    Accounting::Invoice.from(ranked, :accounting_invoices).where("history_rank <= ?", RECENT + 1).order(invoice_date: :desc, id: :desc).group_by { |i| [ i.partner_id, i.currency ] }
  end
  private_class_method :latest_by_supplier
end
