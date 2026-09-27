# Read-only view of journal_entry_lines belonging to a posted journal_entry,
# with entry.entry_date/journal_id/fiscal_year_id/reference denormalized in.
# Reports query this instead of the raw tables (docs/dev/reports/spec.md §3).
class Accounting::PostedLine < ApplicationRecord
  self.table_name = "posted_lines"
  self.primary_key = "id"

  acts_as_tenant :entity

  belongs_to :account,       class_name: "Accounting::Account"
  belongs_to :partner,       class_name: "Accounting::Partner", optional: true
  belongs_to :journal_entry, class_name: "Accounting::JournalEntry"

  def readonly?
    true
  end
end
