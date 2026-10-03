class UserEntity < ApplicationRecord
  include Accounting::AuditTrailed # who gave or took which right, when (F01)

  belongs_to :user
  belongs_to :entity

  enum :role, { admin: 0, accountant: 1, manager: 2, auditor: 3, assistant: 4 }

  # What each role is called on screen (the stored names predate the five roles of docs/dev/features/spec.md §4).
  LABELS = { "admin" => "Owner", "accountant" => "Accountant", "assistant" => "Assistant", "manager" => "Reader", "auditor" => "External auditor" }.freeze

  def self.label_for(role) = LABELS.fetch(role.to_s)
  def self.options_for_select = roles.keys.map { |role| [ label_for(role), role ] }

  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :entity_id, message: :taken }
  validate  :window_not_inverted
  validate  :auditor_access_ends, if: -> { new_record? || will_save_change_to_role? || will_save_change_to_valid_until? }
  validate  :keep_an_owner, on: :update

  # Deleting the whole entity takes its memberships with it; deleting a user account must not take the last owner.
  before_destroy :keep_an_owner_before_destroy, unless: -> { destroyed_by_association&.active_record == Entity }

  scope :active, -> { where(active: true) }
  # The memberships that give access today: active, and inside the validity window (both ends included).
  scope :current, -> {
    active.where("(valid_from IS NULL OR valid_from <= :today) AND (valid_until IS NULL OR valid_until >= :today)", today: Date.current)
  }
  # An owner never expires: an entity must always keep one.
  scope :owners, -> { admin.active.where(valid_until: nil) }

  def owner? = admin? && active? && valid_until.nil?

  private

  # An external auditor's access is limited in time (spec §4). Only checked when the role or the end date changes, so an
  # access granted before this rule is never rewritten behind anyone's back.
  def auditor_access_ends
    errors.add(:valid_until, :auditor_needs_end) if auditor? && valid_until.nil?
  end

  def window_not_inverted
    errors.add(:valid_until, :invalid) if valid_from && valid_until && valid_until < valid_from
  end

  def was_owner? = role_in_database == "admin" && active_in_database && valid_until_in_database.nil?

  def last_owner? = was_owner? && !UserEntity.owners.where(entity_id: entity_id).where.not(id: id).exists?

  def keep_an_owner
    errors.add(:base, :last_owner) if last_owner? && !owner?
  end

  def keep_an_owner_before_destroy
    return unless last_owner?

    errors.add(:base, :last_owner)
    throw :abort
  end
end
