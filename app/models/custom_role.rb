# A role an owner composes from the fine permissions of Permissions::MATRIX (F01, spec §4). An access holding one gets
# exactly these permissions instead of those of its system role. User administration stays with the owners.
class CustomRole < ApplicationRecord
  include Accounting::AuditTrailed

  RESERVED = %w[users.manage].freeze
  ASSIGNABLE = (Permissions::MATRIX.keys - RESERVED).freeze

  acts_as_tenant :entity

  has_many :user_entities, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :entity_id }
  validate  :permissions_are_known_and_assignable

  def permissions=(list)
    super(Array(list).map(&:to_s).reject(&:blank?).uniq)
  end

  private

  def permissions_are_known_and_assignable
    unknown = permissions - Permissions::MATRIX.keys
    errors.add(:permissions, "unknown: #{unknown.join(', ')}") if unknown.any?
    errors.add(:permissions, "#{(permissions & RESERVED).join(', ')} is reserved to the owners") if (permissions & RESERVED).any?
  end
end
