# The only exception to a period lock (F01): a window an owner opens for migration or closing, limited in time, with a
# reason, one at a time per entity. Inside `within`, the PostgreSQL guard lets the block write into locked periods;
# outside, nothing does. Every opening, use and closing is in the audit trail.
class Accounting::ControlledWindow < ApplicationRecord
  self.table_name = "accounting_controlled_windows"

  PURPOSES = %w[migration closing].freeze
  MAX_HOURS = 8

  class Closed < StandardError; end

  acts_as_tenant :entity

  belongs_to :opened_by, class_name: "User"
  belongs_to :closed_by, class_name: "User", optional: true

  validates :purpose, inclusion: { in: PURPOSES }
  validates :reason, :opens_at, :expires_at, presence: true

  scope :open_now, -> { where(closed_at: nil).where("opens_at <= :now AND expires_at > :now", now: Time.current) }

  # Runs the block with the period lock lifted, for the entity's open window of that purpose. Raises Closed otherwise.
  def self.within(purpose:)
    window = open_now.find_by(purpose: purpose) or raise Closed, "No controlled window is open for #{purpose}"

    transaction do
      Accounting::AuditLog.record!(auditable: window, action: "controlled_window_used", user: window.opened_by,
                                   payload: { purpose: purpose, window_id: window.id })
      connection.execute("SELECT set_config('ledgerflow.lock_override', 'on', true)")
      yield
    ensure
      connection.execute("SELECT set_config('ledgerflow.lock_override', 'off', true)")
    end
  end
end
