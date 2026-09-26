# Who should be reminded to pay, from the customer invoices that are overdue at `as_of`: one row per customer, the
# customer that is the latest to pay first. `level` is the firmness of the next reminder (1 to 3); `remindable` is false
# while the last reminder is less than MIN_DAYS_BETWEEN days old. A reminder that failed to go out does not count.
class Accounting::OverdueReminders
  MIN_DAYS_BETWEEN = 14
  MAX_LEVEL = 3
  Row = Struct.new(:partner, :invoices, :total_due, :days_overdue, :level, :last_reminder, :remindable, keyword_init: true) do
    def email = partner.email
  end

  def self.call(as_of: Date.current) = new(as_of).call

  def initialize(as_of)
    @as_of = as_of
  end

  def call
    open_invoices.group_by(&:partner).map { |partner, invoices| row(partner, invoices) }.sort_by { |r| -r.days_overdue }
  end

  private

  def open_invoices
    Accounting::Invoice
      .where(invoice_type: :customer, document_type: :invoice, status: %i[posted partially_paid])
      .where("due_date < ?", @as_of)
      .includes(:partner, :credit_notes)
      .select { |invoice| invoice.remaining_amount.positive? }
  end

  def row(partner, invoices)
    reminders = reminders_covering(invoices)
    last = reminders.max_by { |r| [ r.created_at, r.id ] }

    Row.new(partner: partner, invoices: invoices.sort_by(&:due_date),
            total_due: invoices.sum(&:remaining_amount), days_overdue: (@as_of - invoices.map(&:due_date).min).to_i,
            level: [ reminders.map(&:level).max.to_i + 1, MAX_LEVEL ].min, last_reminder: last,
            remindable: last.nil? || last.created_at.to_date + MIN_DAYS_BETWEEN <= @as_of)
  end

  def reminders_covering(invoices)
    Accounting::PaymentReminder.where.not(status: :failed).joins(:items)
                               .where(accounting_payment_reminder_items: { invoice_id: invoices.map(&:id) }).distinct.to_a
  end
end
