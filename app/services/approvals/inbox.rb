# What waits for one person (B01a "À approuver"): the pending requests whose current level they may decide on (named, through a role,
# called in by a timer, or standing in for someone), the earliest payment due date first, then the oldest.
# Filters: supplier (part of the name), min_amount / max_amount (incl. VAT, in EUR), project_id.
# Everything is read in a handful of queries whatever the length of the list (spec/performance/approvals_spec.rb): the people of the entity once
# (Approvals::Directory), the amounts and the history of the suppliers grouped.
class Approvals::Inbox
  Row = Struct.new(:request, :invoice, :amount, :warnings, keyword_init: true)

  def self.for(user, filters = {}, directory: nil) = new(user, filters, directory).rows

  def self.count(user, directory: nil) = new(user, {}, directory).requests.size

  def initialize(user, filters, directory)
    @user = user
    @filters = filters.to_h.symbolize_keys
    @directory = directory || Approvals::Directory.new
  end

  def rows
    invoices = requests.map(&:subject)
    raw = Accounting::InvoiceLine.unscope(:order).where(invoice_id: invoices.map(&:id)).group(:invoice_id).sum(:total_incl_vat) # the database adds up
    histories = Approvals::SupplierHistory.for_many(invoices, amounts: raw)
    rows = requests.map do |request|
      invoice = request.subject
      Row.new(request: request, invoice: invoice, amount: Fx::Convert.to_eur(raw.fetch(invoice.id, 0), invoice.exchange_rate), warnings: histories.fetch(invoice.id).warnings)
    end
    filter(rows).sort_by { |row| [ row.invoice.due_date || Date.new(9999), row.request.submitted_at || row.request.created_at ] }
  end

  def requests
    @requests ||= Approvals::Request.pending.includes(policy: :steps, subject: %i[partner entity]).select { |request| Approvals::Approvers.for(request, @directory).key?(@user.id) }
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
