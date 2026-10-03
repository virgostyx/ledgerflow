# The lines of a lettering that closes with a rounding difference (F04), waiting for the draft adjustment entry to be validated.
class Accounting::LetteringWriteOff < ApplicationRecord
  self.table_name = "accounting_lettering_write_offs"

  acts_as_tenant :entity

  belongs_to :journal_entry, class_name: "Accounting::JournalEntry"
  belongs_to :created_by, class_name: "User", optional: true

  scope :pending, -> { where(completed_at: nil) }

  def self.pending_for?(line_ids) = pending.where("line_ids && ARRAY[?]::bigint[]", line_ids).exists?
end
