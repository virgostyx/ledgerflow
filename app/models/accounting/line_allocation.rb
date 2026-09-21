# Part of a debit line settled against part of a credit line (partial lettering). When every line linked by
# allocations is fully allocated, the group is closed into a regular total Lettering (Accounting::AllocateLines).
class Accounting::LineAllocation < ApplicationRecord
  self.table_name = "accounting_line_allocations"

  acts_as_tenant :entity

  belongs_to :debit_line,  class_name: "Accounting::JournalEntryLine"
  belongs_to :credit_line, class_name: "Accounting::JournalEntryLine"

  validates :amount, numericality: { greater_than: 0 }
  validates :allocated_on, presence: true

  # The given lines plus every line linked to them by allocations, however far.
  def self.group_lines(lines)
    ids = lines.map(&:id).to_set
    frontier = ids.to_a
    while frontier.any?
      linked   = touching(frontier).pluck(:debit_line_id, :credit_line_id).flatten.uniq
      frontier = linked - ids.to_a
      ids.merge(frontier)
    end
    Accounting::JournalEntryLine.where(id: ids.to_a).includes(:journal_entry, :account, :invoice).to_a
  end

  scope :touching, ->(line_ids) { where(debit_line_id: line_ids).or(where(credit_line_id: line_ids)) }
end
