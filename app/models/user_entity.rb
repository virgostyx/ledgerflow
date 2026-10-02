class UserEntity < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  enum :role, { admin: 0, accountant: 1, manager: 2, auditor: 3 }

  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :entity_id, message: :taken }
  validate  :window_not_inverted
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
