# One due date of a recurring entry (F07): what was made for it, or why not. Unique per recurring entry and due date.
class Accounting::RecurringRun < ApplicationRecord
  self.table_name = "accounting_recurring_runs"

  acts_as_tenant :entity

  enum :status, { generated: 0, blocked: 1, failed: 2, skipped: 3 }

  belongs_to :recurring_entry, class_name: "Accounting::RecurringEntry", optional: true, inverse_of: :runs
  belongs_to :journal_entry, class_name: "Accounting::JournalEntry", optional: true

  validates :due_on, :recurring_name, presence: true
end
