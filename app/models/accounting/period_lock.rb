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

  # A temporary unlock closes again at relock_at, even before the job that flips the status has run.
  scope :in_force, -> { where("status = :locked OR (relock_at IS NOT NULL AND relock_at <= :now)", locked: statuses[:locked], now: Time.current) }
  scope :due_for_relock, -> { unlocked.where("relock_at <= ?", Time.current) }

  # The locks that forbid an entry dated `date` (first and last day included).
  scope :covering, ->(date) { in_force.where("starts_on <= :d AND ends_on >= :d", d: date) }

  # Serialises whoever locks, unlocks or opens a window for one entity, so a check-then-write (is it already locked?
  # is a window open?) cannot be raced by a second request. Held until the end of the current transaction.
  def self.serialize_for_entity!(entity_id = ActsAsTenant.current_tenant&.id)
    connection.execute("SELECT pg_advisory_xact_lock(hashtext('accounting_period_locks'), #{entity_id.to_i})")
  end

  private

  def ends_on_not_before_starts_on
    errors.add(:ends_on, :invalid) if starts_on && ends_on && ends_on < starts_on
  end
end
