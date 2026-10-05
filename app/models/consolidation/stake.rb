class Consolidation::Stake < ApplicationRecord
  belongs_to :member, class_name: "Consolidation::Member", foreign_key: :consolidation_member_id, inverse_of: :stakes

  validates :percentage, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :effective_on, presence: true, uniqueness: { scope: :consolidation_member_id }
end
