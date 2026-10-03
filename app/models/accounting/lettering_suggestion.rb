# A proposed lettering (F04): lines of one account and partner that settle each other, with the rule that found them and
# its score. Accepting it letters the lines; rejecting it keeps it out of the proposals until its lines change.
class Accounting::LetteringSuggestion < ApplicationRecord
  self.table_name = "accounting_lettering_suggestions"

  enum :status, { proposed: 0, accepted: 1, rejected: 2 }

  # rule number => score (docs/dev/features/spec.md §7)
  SCORES = { 1 => 100, 2 => 95, 3 => 90, 4 => 85, 5 => 80, 6 => 70 }.freeze

  acts_as_tenant :entity

  belongs_to :account, class_name: "Accounting::Account"
  belongs_to :partner, class_name: "Accounting::Partner", optional: true
  belongs_to :decided_by, class_name: "User", optional: true

  validates :rule, inclusion: { in: SCORES.keys }
  validates :line_ids, :fingerprint, presence: true

  def lines = Accounting::JournalEntryLine.where(id: line_ids)

  def reject!(user) = update!(status: :rejected, decided_by: user, decided_at: Time.current)
end
