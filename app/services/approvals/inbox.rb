# What waits for one person (B01a "À approuver"): the pending requests whose current level they may decide on (named, through a role,
# called in by a timer, or standing in for someone), the earliest payment due date first, then the oldest.
# Filters: supplier (part of the name), min_amount / max_amount (incl. VAT, in EUR), project_id.
# ponytail: one lookup of the approvers per pending request; fine for hundreds, to be measured against the 500 ms budget at 500 items.
class Approvals::Inbox
  Row = Struct.new(:request, :invoice, :amount, :warnings, keyword_init: true)

  def self.for(user, filters = {}) = new(user, filters).rows

  def self.count(user) = new(user, {}).requests.size

  def initialize(user, filters)
    @user = user
    @filters = filters.to_h.symbolize_keys
  end

  def rows
    amounts = Accounting::InvoiceLine.unscope(:order).where(invoice_id: requests.map(&:subject_id)).group(:invoice_id).sum(:total_incl_vat) # the database adds up
    rows = requests.map do |request|
      invoice = request.subject
      Row.new(request: request, invoice: invoice, amount: Fx::Convert.to_eur(amounts.fetch(invoice.id, 0), invoice.exchange_rate),
              warnings: Approvals::SupplierHistory.for(invoice).warnings)
    end
    filter(rows).sort_by { |row| [ row.invoice.due_date || Date.new(9999), row.request.submitted_at || row.request.created_at ] }
  end

  def requests
    @requests ||= Approvals::Request.pending.includes(:policy, subject: %i[partner entity]).select { |request| Approvals::Approvers.for(request).key?(@user.id) }
  end

  private

  def filter(rows)
    rows = rows.select { |r| r.invoice.partner.name.downcase.include?(@filters[:supplier].to_s.downcase) } if @filters[:supplier].present?
    rows = rows.select { |r| r.amount >= @filters[:min_amount].to_d } if @filters[:min_amount].present?
    rows = rows.select { |r| r.amount <= @filters[:max_amount].to_d } if @filters[:max_amount].present?
    rows = rows.select { |r| r.invoice.project_id == @filters[:project_id].to_i } if @filters[:project_id].present?
    rows
  end
end
