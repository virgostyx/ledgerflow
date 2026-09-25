# Generates the drafts that the active recurring invoices of the current entity owe up to `on`: one per missed date, at
# most MAX_CATCH_UP per recurrence and run. A draft is never posted here. A recurrence that fails records its error
# and stops (it tries again at the next run) without holding up the others.
class Accounting::RunRecurringInvoices
  MAX_CATCH_UP = 12

  def self.call(on: Date.current)
    ctx = LightService::Context.make(generated: [], failed: [])
    Accounting::RecurringInvoice.where(active: true).order(:id).each { |recurring| run(recurring, on, ctx) }
    ctx
  end

  def self.run(recurring, on, ctx)
    MAX_CATCH_UP.times do
      break unless recurring.due?(on)

      error = generate(recurring, ctx)
      next unless error

      recurring.update_columns(last_error: error, updated_at: Time.current)
      ctx[:failed] << recurring
      break
    end
  end

  # Nil when a draft was generated (added to ctx[:generated]); the error message otherwise.
  def self.generate(recurring, ctx)
    source = recurring.source_invoice
    return I18n.t("accounting.recurring_invoices.errors.source_cancelled") if source.cancelled?

    draft = error = nil
    ApplicationRecord.transaction do
      date   = recurring.next_run_on
      result = Accounting::DuplicateInvoice.call(invoice: source, invoice_date: date)
      if result.failure?
        error = result.message
        next
      end

      draft = result[:invoice]
      draft.update!(recurring_invoice: recurring)
      recurring.update!(runs_count: recurring.runs_count + 1, last_run_on: date, last_error: nil)
    end
    ctx[:generated] << draft if draft
    error
  rescue StandardError => e
    "Error: #{e.message}"
  end

  private_class_method :run, :generate
end
