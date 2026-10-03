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

  encrypts :totp_secret

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
  def generate_recovery_codes!(kind: :passkey)
    codes = Array.new(RECOVERY_CODE_COUNT) { SecureRandom.hex(5) }
    transaction do
      recovery_codes.where(kind: kind).destroy_all
      codes.each { |c| recovery_codes.create!(kind: kind, code_digest: BCrypt::Password.create(c)) }
    end
    codes
  end

  def use_recovery_code!(code, kind: :passkey)
    match = recovery_codes.where(kind: kind).unused.find { |rc| BCrypt::Password.new(rc.code_digest) == code.to_s.strip.downcase }
    match ? match.update!(used_at: Time.current) : false
  end

  # Backup codes of the second factor: shown once, each usable once at the challenge instead of an app code.
  def generate_totp_backup_codes! = generate_recovery_codes!(kind: :totp)

  def use_totp_backup_code!(code) = use_recovery_code!(code, kind: :totp)

  # --- Second factor (F01) ----------------------------------------------------------------------------------

  def totp_enabled? = totp_enabled_at.present?

  # Whoever can validate, unlock or administer in an entity where F01 is on must sign in with a second factor.
  def second_factor_required?
    user_entities.current.includes(:entity).any? { |membership| membership.sensitive? && membership.entity.feature?(:f01) }
  end

  # A new secret to show (as text and QR code) until a code from the app confirms it; the same one on a revisit.
  def begin_totp_enrollment!
    return totp_secret if totp_secret.present? && !totp_enabled?

    update!(totp_secret: Totp.generate_secret, totp_enabled_at: nil, totp_last_step: nil)
    totp_secret
  end

  def confirm_totp!(code)
    return false if totp_secret.blank? || totp_enabled?

    step = Totp.verify(totp_secret, code)
    return false unless step

    update!(totp_enabled_at: Time.current, totp_last_step: step)
    true
  end

  # True once per code: the step is recorded atomically, so two simultaneous uses of the same code cannot both pass.
  def verify_totp!(code)
    return false unless totp_enabled?

    step = Totp.verify(totp_secret, code, after_step: totp_last_step)
    return false unless step

    User.where(id: id).where("totp_last_step IS NULL OR totp_last_step < ?", step).update_all(totp_last_step: step) == 1
  end

  def disable_totp!
    transaction do
      recovery_codes.totp.destroy_all
      update!(totp_secret: nil, totp_enabled_at: nil, totp_last_step: nil)
    end
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
