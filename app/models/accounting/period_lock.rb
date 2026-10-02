# A closed range of accounting dates (F01). While locked, nothing may be posted with an entry date inside it.
# The audit trail is written by Accounting::LockPeriod / UnlockPeriod (one entry per action, with the reason).
class Accounting::PeriodLock < ApplicationRecord
  self.table_name = "accounting_period_locks"

  acts_as_tenant :entity

  enum :kind,   { accounting: 0, vat: 1, fiscal_year: 2 }
  enum :status, { locked: 0, unlocked: 1 }

  belongs_to :locked_by,   class_name: "User"
  belongs_to :unlocked_by, class_name: "User", optional: true

  validates :starts_on, :ends_on, presence: true
  validate  :ends_on_not_before_starts_on

  # The locks that forbid an entry dated `date` (first and last day included).
  scope :covering, ->(date) { locked.where("starts_on <= :d AND ends_on >= :d", d: date) }

  private

  def ends_on_not_before_starts_on
    errors.add(:ends_on, :invalid) if starts_on && ends_on && ends_on < starts_on
  end
end
