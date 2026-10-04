# A ledger line covered by a reminder, with what was still owed on it when the reminder was prepared.
class Accounting::DunningItemLine < ApplicationRecord
  self.table_name = "dunning_item_lines"

  acts_as_tenant :entity

  belongs_to :item, class_name: "Accounting::DunningItem", foreign_key: :dunning_item_id, inverse_of: :item_lines
  belongs_to :line, class_name: "Accounting::JournalEntryLine"

  # Read like a row of Accounting::UnletteredLinesQuery, which is what the text of a reminder is written from.
  def residual = amount
  def age_days = (item.run_on - due_date).to_i
  def reference = line.journal_entry.reference
end
