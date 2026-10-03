class UserEntity < ApplicationRecord
  include Accounting::AuditTrailed # who gave or took which right, when (F01)

  belongs_to :user
  belongs_to :entity
  belongs_to :custom_role, optional: true

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
  validate  :journals_of_the_entity
  validate  :custom_role_is_valid_here

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

  # journal_ids: the journals this access is limited to; nil (or an empty selection) means every journal.
  def journal_ids=(ids)
    whole = Array(ids).filter_map { |id| Integer(id.to_s, exception: false) }.uniq
    super(whole.presence)
  end

  def allows_journal?(journal_id) = journal_ids.nil? || journal_ids.include?(journal_id)

  # One question for every right (F01): the custom role's permissions when the access has one, else its system role's.
  # An unknown permission raises either way: a typo must never become a silent denial.
  def allows?(permission)
    Permissions::MATRIX.fetch(permission.to_s)
    custom_role ? custom_role.permissions.include?(permission.to_s) : Permissions.allowed?(role, permission)
  end

  # Whoever can validate, unlock or administer signs in with a second factor.
  def sensitive? = Permissions::SENSITIVE.any? { |permission| allows?(permission) }

  private

  # An external auditor's access is limited in time (spec §4). Only checked when the role or the end date changes, so an
  # access granted before this rule is never rewritten behind anyone's back.
  def auditor_access_ends
    errors.add(:valid_until, :auditor_needs_end) if auditor? && valid_until.nil?
  end

  # A custom role is never an owner, and belongs to the entity of the access.
  def custom_role_is_valid_here
    return unless custom_role

    errors.add(:custom_role, :invalid) if custom_role.entity_id != entity_id || admin?
  end

  def journals_of_the_entity
    return if journal_ids.blank?

    known = ActsAsTenant.with_tenant(entity) { Accounting::Journal.where(id: journal_ids).pluck(:id) }
    errors.add(:journal_ids, :invalid) unless known.sort == journal_ids.sort
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
