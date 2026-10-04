# A journal entry that comes back on a schedule (F07): an entry template run monthly, quarterly or yearly, as a draft (the default) or,
# when an owner approved it, posted by itself. Accounting::GenerateRecurringEntries makes the entries. Only a template whose amounts are
# known in advance can be scheduled (no line typed each time), which is also what lets an owner approve it.
class Accounting::RecurringEntry < ApplicationRecord
  include Accounting::AuditTrailed
  self.table_name = "accounting_recurring_entries"

  STEP_MONTHS = { "monthly" => 1, "quarterly" => 3, "yearly" => 12 }.freeze

  acts_as_tenant :entity

  enum :frequency, { monthly: 0, quarterly: 1, yearly: 2 }
  enum :mode,      { draft: 0, post: 1 }, prefix: true
  enum :status,    { active: 0, paused: 1, finished: 2, blocked: 3 }

  belongs_to :entry_template, class_name: "Accounting::EntryTemplate", inverse_of: :recurring_entries
  belongs_to :created_by,       class_name: "User", optional: true
  belongs_to :post_approved_by, class_name: "User", optional: true
  has_many   :runs, class_name: "Accounting::RecurringRun", foreign_key: :recurring_entry_id, inverse_of: :recurring_entry, dependent: :nullify

  validates :name, :starts_on, presence: true
  validates :day_of_month, inclusion: { in: 1..31 }, allow_nil: true
  validates :max_occurrences, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :lead_days, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :indexation_percent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :base_amount, numericality: { greater_than: 0 }, if: -> { entry_template&.needs_base? }
  validate  :ends_on_not_before_starts_on
  validate  :template_amounts_are_known
  validate  :post_mode_is_approved

  before_validation :set_first_due_date, on: :create
  before_validation :fall_back_to_draft, on: :update

  scope :due_by, ->(date) { where(status: %i[active blocked]).where("next_due_on - lead_days * INTERVAL '1 day' <= ?", date) }

  # The date of the occurrence in the month of `month_start`: the day asked for, or the last day when the month is shorter or none is asked.
  def date_in(month_start)
    last = month_start.end_of_month
    day_of_month ? [ month_start.change(day: 1) + (day_of_month - 1), last ].min : last
  end

  def following(due_on) = date_in((due_on.beginning_of_month >> STEP_MONTHS.fetch(frequency)))

  # `count` due dates from the next one on (the preview; stops at the end of the schedule)
  def upcoming_dates(count)
    dates = []
    date = next_due_on
    while dates.size < count && (ends_on.nil? || date <= ends_on) && (max_occurrences.nil? || occurrences_count + dates.size < max_occurrences)
      dates << date
      date = following(date)
    end
    dates
  end

  def last_run = runs.order(:due_on).last

  # The amount the entry will have on a date: the base amount with the indexation of the years not yet applied.
  def amount_on(date)
    amount = base_amount
    return amount if amount.nil? || indexation_percent.blank?

    ((indexed_year || starts_on.year) + 1..date.year).each { amount = (amount * (1 + indexation_percent / 100)).round(2, half: :up) }
    amount
  end

  # What the entry weighs on the cash (R14): an outflow when it charges an expense account (class 6), an inflow when it credits revenue (class 7).
  def forecast_direction
    lines = entry_template.lines
    return :out if lines.any? { |l| l.debit? && l.account.account_class == 6 }

    :in if lines.any? { |l| l.credit? && l.account.account_class == 7 }
  end

  def forecast_amount(date) = Accounting::BuildEntryFromTemplate.total_for(entry_template, amount_on(date))

  # Set by Accounting::ApproveRecurringPost: not through a form, so that nobody approves by editing.
  attr_accessor :approving

  private

  def set_first_due_date
    return if next_due_on || starts_on.nil?

    first = date_in(starts_on.beginning_of_month)
    self.next_due_on = first < starts_on ? following(first) : first
  end

  # A change of the template or the amount takes the approval back: the owner approved something else.
  def fall_back_to_draft
    return unless mode_post? && !approving && (will_save_change_to_entry_template_id? || will_save_change_to_base_amount?)

    self.mode = :draft
    self.post_approved_by = nil
    self.post_approved_at = nil
  end

  def ends_on_not_before_starts_on
    errors.add(:ends_on, :invalid) if ends_on && starts_on && ends_on < starts_on
  end

  def template_amounts_are_known
    errors.add(:entry_template, "has a line typed each time: only a template whose amounts are known can be scheduled") if entry_template && !entry_template.fixed_amounts_only?
  end

  def post_mode_is_approved
    errors.add(:mode, "post must be approved by an owner") if mode_post? && post_approved_by_id.blank?
  end
end
