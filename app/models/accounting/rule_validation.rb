# An accountant's validation of one accounting rule set of the company: who, in what capacity, when, where it is written.
# Screens that depend on the rule show a "not validated" notice until one is in force.
class Accounting::RuleValidation < ApplicationRecord
  self.table_name = "accounting_rule_validations"

  acts_as_tenant :entity

  RULES = %w[vat_declaration annual_accounts].freeze

  validates :rule_key, inclusion: { in: RULES }
  validates :validated_by_name, :validated_by_title, :validated_on, :reference, presence: true
  validate :not_in_the_future

  scope :in_force, -> { where(revoked_at: nil) }

  def self.validated?(rule_key) = in_force.exists?(rule_key: rule_key)

  def revoke! = update!(revoked_at: Time.current)

  private

  def not_in_the_future
    errors.add(:validated_on, "cannot be in the future") if validated_on && validated_on > Date.current
  end
end
