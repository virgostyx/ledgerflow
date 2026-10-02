class User < ApplicationRecord
  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable,
         :lockable,
         :timeoutable,
         :trackable

  enum :role, { admin: 0, accountant: 1, manager: 2, auditor: 3, budget_user: 4 }

  has_many :user_entities, dependent: :destroy
  has_many :entities, through: :user_entities
  # The entities the user may work in today (active membership inside its validity window).
  has_many :current_entities, -> { merge(UserEntity.current) }, through: :user_entities, source: :entity
  has_many :webauthn_credentials, dependent: :destroy
  has_many :recovery_codes, dependent: :destroy

  RECOVERY_CODE_COUNT = 10

  validates :full_name, presence: true
  validates :email,     presence: true

  scope :active, -> { where(active: true) }

  def active_for_authentication?
    super && active?
  end

  def inactive_message
    active? ? super : :inactive_account
  end

  # First passkey turns the account passwordless (derived, not stored).
  def passwordless?
    webauthn_credentials.exists?
  end

  def webauthn_id
    super || WebAuthn.generate_user_id.tap { |id| update_column(:webauthn_id, id) }
  end

  # Returns the plain codes (shown once); only BCrypt digests are stored.
  def generate_recovery_codes!
    codes = Array.new(RECOVERY_CODE_COUNT) { SecureRandom.hex(5) }
    transaction do
      recovery_codes.destroy_all
      codes.each { |c| recovery_codes.create!(code_digest: BCrypt::Password.create(c)) }
    end
    codes
  end

  def use_recovery_code!(code)
    match = recovery_codes.unused.find { |rc| BCrypt::Password.new(rc.code_digest) == code.to_s.strip.downcase }
    match ? match.update!(used_at: Time.current) : false
  end

  # Every failed password attempt is audited (with the count, and whether it locked the account).
  def valid_for_authentication?
    super.tap do |valid|
      Accounting::AuditLogin.call(user: self, action: "login_failed", method: "password", failed_attempts: failed_attempts, locked: access_locked?) unless valid
    end
  end

  def can_post_entries?
    admin? || accountant?
  end

  def can_manage_invoices?
    admin? || accountant? || manager?
  end
end
