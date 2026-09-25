# A schedule that turns an issued invoice into a new draft at each due date (Accounting::RunRecurringInvoices).
# The source invoice is copied as it is at run time; the generated drafts are never posted automatically.
class Accounting::RecurringInvoice < ApplicationRecord
  self.table_name = "accounting_recurring_invoices"

  acts_as_tenant :entity

  STEP_MONTHS = { "monthly" => 1, "quarterly" => 3, "yearly" => 12 }.freeze

  enum :frequency, { monthly: 0, quarterly: 1, yearly: 2 }

  belongs_to :source_invoice, class_name: "Accounting::Invoice"
  has_many   :generated_invoices, class_name: "Accounting::Invoice", foreign_key: :recurring_invoice_id,
                                  inverse_of: :recurring_invoice, dependent: :nullify

  validates :start_on, presence: true
  validate  :end_on_not_before_start_on
  validate  :source_is_an_issued_invoice, on: :create

  # runs_count counts the periods that have gone by, generated or skipped (see #resume!). The next date is counted from
  # the first date, not from the previous run, so a 31st never drifts after a short month.
  def next_run_on = start_on >> (runs_count * STEP_MONTHS.fetch(frequency))

  def ended? = end_on.present? && next_run_on > end_on

  def due?(on) = active? && !ended? && next_run_on <= on

  def status
    return :ended if ended?

    active? ? :active : :paused
  end

  # Reactivates a paused recurrence, skipping the dates that came and went meanwhile: no burst of drafts.
  def resume!(on: Date.current)
    self.runs_count += 1 while next_run_on < on
    update!(active: true)
  end

  def pending_drafts_count = generated_invoices.draft.count

  private

  def end_on_not_before_start_on
    errors.add(:end_on, "cannot be before the first date") if start_on && end_on && end_on < start_on
  end

  def source_is_an_issued_invoice
    return if source_invoice&.invoice? && source_invoice.issued?

    errors.add(:source_invoice, "must be an issued invoice, not a draft or a credit note")
  end
end
