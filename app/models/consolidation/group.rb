# A group of companies to consolidate, seen from its parent company (the tenant). The parent is a member of its own group, at 100 %.
class Consolidation::Group < ApplicationRecord
  acts_as_tenant :entity

  has_many :members, class_name: "Consolidation::Member", foreign_key: :consolidation_group_id, inverse_of: :group, dependent: :destroy
  has_many :runs, class_name: "Consolidation::Run", foreign_key: :consolidation_group_id, inverse_of: :group, dependent: :destroy
  has_many :mappings, class_name: "Consolidation::Mapping", foreign_key: :consolidation_group_id, inverse_of: :group, dependent: :destroy
  has_many :rule_validations, class_name: "Consolidation::RuleValidation", foreign_key: :consolidation_group_id, inverse_of: :group, dependent: :destroy

  validates :name, presence: true
  validates :currency, inclusion: { in: Accounting::MoneyPresenter::SUPPORTED_CURRENCIES }

  # The validation in force of a rule (an accountant's, with the parameters that were validated), or nil: the rule is then not applied.
  def validation_for(rule_key) = rule_validations.in_force.find_by(rule_key: rule_key.to_s)

  def member_entities = Entity.where(id: members.map(&:member_entity_id))
end
