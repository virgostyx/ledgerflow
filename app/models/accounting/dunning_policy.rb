# The rules of the customer reminders of an entity (F09): the three levels and the delay after the due date at which each starts, the smallest amount
# worth a reminder, optional charges, and the sender. One row per entity, made on first use. Late interest and the fixed indemnity are off until the
# accountant types the figures: no legal rate lives in the code (they depend on the law and on the contract, see QUESTIONS.md).
class Accounting::DunningPolicy < ApplicationRecord
  self.table_name = "dunning_policies"

  acts_as_tenant :entity

  LEVELS = [ 1, 2, 3 ].freeze

  validates :level_1_days, :level_2_days, :level_3_days, :follow_up_days, :min_days_between, numericality: { only_integer: true, greater_than: 0 }
  validates :min_amount, :fee_1, :fee_2, :fee_3, numericality: { greater_than_or_equal_to: 0 }
  validates :interest_rate,    numericality: { greater_than_or_equal_to: 0 }, if: :interest_enabled
  validates :indemnity_amount, numericality: { greater_than_or_equal_to: 0 }, if: :indemnity_enabled
  validate  :levels_are_in_order, :templates_are_valid

  def self.for(entity) = ActsAsTenant.with_tenant(entity) { find_or_create_by!(entity: entity) }

  def days_for(level) = public_send(:"level_#{level}_days")
  def fee_for(level)  = public_send(:"fee_#{level}")

  # The level that the delay (days past the due date) has reached: 0 before the first level starts.
  def level_for_delay(days) = LEVELS.reverse.find { |level| days >= days_for(level) }.to_i

  private

  def templates_are_valid
    Accounting::DunningTexts.errors_in(templates).each { |message| errors.add(:templates, message) }
  end

  def levels_are_in_order
    return if level_1_days.to_i < level_2_days.to_i && level_2_days.to_i < level_3_days.to_i

    errors.add(:base, "The delays of the levels must increase")
  end
end
