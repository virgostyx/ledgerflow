# An accountant's validation of one consolidation rule: who, in what capacity, when, where it is written (the QUESTIONS.md section, a letter), and the
# parameters that were validated. A rule is applied only while one is in force, and only with the parameters it holds: what was validated is what runs.
class Consolidation::RuleValidation < ApplicationRecord
  belongs_to :group, class_name: "Consolidation::Group", foreign_key: :consolidation_group_id, inverse_of: :rule_validations
  belongs_to :recorded_by, class_name: "User", optional: true

  validates :rule_key, inclusion: { in: ->(_) { Consolidation::Rules.keys } }
  validates :validated_by_name, :validated_by_title, :validated_on, :reference, presence: true
  validate :parameters_complete, :not_in_the_future

  scope :in_force, -> { where(revoked_at: nil) }

  def revoke! = update!(revoked_at: Time.current)

  private

  def parameters_complete
    missing = Consolidation::Rules.fetch(rule_key)[:parameters].keys.map(&:to_s) - parameters.keys.map(&:to_s) if Consolidation::Rules.keys.include?(rule_key)
    errors.add(:parameters, "lack: #{missing.join(', ')}") if missing.present?
  end

  def not_in_the_future
    errors.add(:validated_on, "cannot be in the future") if validated_on && validated_on > Date.current
  end
end
