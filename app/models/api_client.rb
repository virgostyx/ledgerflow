class ApiClient < ApplicationRecord
  SCOPES = %w[invoices:read invoices:write partners:write].freeze

  # What each scope lets a key do, as the permission its owner would need to do it by hand (Permissions::MATRIX).
  SCOPE_PERMISSIONS = { "invoices:read" => "records.view", "invoices:write" => "records.write", "partners:write" => "records.write" }.freeze

  # Not acts_as_tenant: the client designates the tenant, it is looked up before any tenant is set.
  belongs_to :entity
  # The person behind the key (F01). nil only for keys issued before F01, which keep working as they did.
  belongs_to :owner, class_name: "User", optional: true

  has_many :api_requests, dependent: :destroy

  validates :name, presence: true
  validates :key_digest, presence: true, uniqueness: true
  validate  :known_scopes
  validate  :entity_uses_budgetflow, on: :create
  validate  :owner_has_access, :scopes_within_owner_rights, if: -> { owner && (new_record? || will_save_change_to_scopes? || will_save_change_to_owner_id?) }

  # Returns [client, plaintext_key]; the key can't be recovered afterwards.
  def self.issue!(**attrs)
    key    = generate_key
    client = create!(attrs.merge(key_digest: digest(key)))
    [ client, key ]
  end

  def self.authenticate(key)
    return if key.blank?

    find_by(key_digest: digest(key), active: true)
  end

  def self.generate_key = "lf_#{SecureRandom.urlsafe_base64(32)}"
  def self.digest(key) = Digest::SHA256.hexdigest(key)

  # A scope is usable while the owner still holds the matching right: removing it takes effect on the next call.
  def allows?(scope) = scopes.include?(scope) && owner_permits?(SCOPE_PERMISSIONS.fetch(scope))

  # The owner's role in this entity today (an expired or deactivated access gives none).
  def owner_membership = owner && UserEntity.current.find_by(user_id: owner_id, entity_id: entity_id)

  def owner_permits?(permission) = owner.nil? || Permissions.allowed?(owner_membership&.role, permission)

  # Posting an invoice validates entries: only a key whose owner may validate.
  def may_post? = owner_permits?("invoices.issue")

  def revoke! = update!(active: false)

  def rotate!
    key = self.class.generate_key
    update!(key_digest: self.class.digest(key))
    key
  end

  private

  def entity_uses_budgetflow
    errors.add(:entity, "did not declare the BudgetFlow integration") unless entity&.budgetflow?
  end

  def owner_has_access
    errors.add(:owner, "has no access to this entity") unless owner_membership
  end

  def scopes_within_owner_rights
    beyond = scopes.select { |scope| SCOPE_PERMISSIONS.key?(scope) && !owner_permits?(SCOPE_PERMISSIONS[scope]) }
    errors.add(:scopes, "exceed the rights of the owner: #{beyond.join(', ')}") if beyond.any?
  end

  def known_scopes
    unknown = scopes - SCOPES
    errors.add(:scopes, "unknown: #{unknown.join(', ')}") if unknown.any?
  end
end
