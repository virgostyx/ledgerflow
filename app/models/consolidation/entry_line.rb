class Consolidation::EntryLine < ApplicationRecord
  SIDES = %w[debit credit].freeze

  belongs_to :entry, class_name: "Consolidation::Entry", foreign_key: :consolidation_entry_id, inverse_of: :lines

  validates :side, inclusion: { in: SIDES }
  validates :statement, inclusion: { in: Accounting::AnnualAccounts::STATEMENTS.map(&:to_s) }
  validates :amount, numericality: { greater_than: 0 }
  validate :heading_exists

  # How this line moves its heading: the heading's amount is positive on its own side, so a line on that side adds and a line on the other subtracts.
  def effect = (Consolidation::Statements.leaf(statement, code)&.fetch("side") == side ? amount : -amount)

  private

  def heading_exists
    errors.add(:code, "is not a heading of the #{statement} statement that holds accounts") unless Consolidation::Statements.leaf(statement, code)
  end
end
