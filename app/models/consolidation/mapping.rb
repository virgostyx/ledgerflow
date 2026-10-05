# A heading of the annual accounts of a company (R07/R08) sent to another heading of the consolidated statements. No row: the same code.
class Consolidation::Mapping < ApplicationRecord
  belongs_to :group, class_name: "Consolidation::Group", foreign_key: :consolidation_group_id, inverse_of: :mappings
  belongs_to :member, class_name: "Consolidation::Member", foreign_key: :consolidation_member_id, optional: true

  validates :statement, inclusion: { in: Accounting::AnnualAccounts::STATEMENTS.map(&:to_s) }
  validates :source_code, :consolidated_code, presence: true
  validate :headings_exist

  private

  def headings_exist
    leaves = Consolidation::Statements.leaf_codes(statement)
    errors.add(:consolidated_code, "is not a heading of the #{statement} statement") unless leaves.include?(consolidated_code)
    errors.add(:source_code, "is not a heading of the #{statement} statement") unless leaves.include?(source_code)
  end
end
