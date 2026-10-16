# B02a: a person from outside the firm. Not a User; there is no link between the two, even for one person.
class PortalUser < ApplicationRecord
  has_secure_password
  encrypts :totp_secret

  enum :status, { invited: "invited", active: "active", suspended: "suspended", revoked: "revoked" }, default: "invited"

  MAX_FAILURES = 5
  LOCK_DURATION = 30.minutes
  BACKUP_CODE_COUNT = 10

  has_many :grants, class_name: "Portal::Grant", dependent: :destroy
  has_many :sessions, class_name: "Portal::Session", dependent: :destroy
  has_many :devices, class_name: "Portal::Device", dependent: :destroy
  has_many :backup_codes, class_name: "Portal::BackupCode", dependent: :destroy
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :identity_verified_by, class_name: "User", optional: true

  normalizes :email, with: ->(email) { email.strip }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { case_sensitive: false }
  validates :full_name, presence: true
  validates :notification_frequency, inclusion: { in: %w[immediate daily off] }
  validates :password, length: { minimum: 12 }, allow_nil: true

  def self.find_by_email(email) = find_by("lower(email) = ?", email.to_s.strip.downcase)

  # The rights in force today, in companies that are active and where the portal is on: every request reads them, so a revocation or an expiry acts at once.
  def open_grants
    grants.in_force.joins(:company).where(portal_companies: { active: true, portal_enabled: true })
  end

  def second_factor_configured? = totp_enabled_at.present?

  def locked? = locked_at.present? && locked_at > LOCK_DURATION.ago

  def register_failure!
    attempts = failed_attempts + 1
    update_columns(failed_attempts: attempts, locked_at: (attempts >= MAX_FAILURES ? Time.current : locked_at))
  end

  def unlock! = update_columns(failed_attempts: 0, locked_at: nil)

  def register_success!
    update_columns(failed_attempts: 0, locked_at: nil, last_sign_in_at: Time.current)
  end

  # A new secret to show until a code confirms it.
  def begin_totp_enrollment!
    return totp_secret if totp_secret.present? && !second_factor_configured?

    update!(totp_secret: Totp.generate_secret, totp_enabled_at: nil, totp_last_step: nil)
    totp_secret
  end

  def confirm_totp!(code)
    return false if totp_secret.blank? || second_factor_configured?

    step = Totp.verify(totp_secret, code)
    return false unless step

    update!(totp_enabled_at: Time.current, totp_last_step: step)
    true
  end

  # True once per code: the step is recorded atomically.
  def verify_totp!(code)
    return false unless second_factor_configured?

    step = Totp.verify(totp_secret, code, after_step: totp_last_step)
    return false unless step

    PortalUser.where(id: id).where("totp_last_step IS NULL OR totp_last_step < ?", step).update_all(totp_last_step: step) == 1
  end

  # Shown once; only BCrypt digests are kept.
  def generate_backup_codes!
    codes = Array.new(BACKUP_CODE_COUNT) { SecureRandom.hex(5) }
    transaction do
      backup_codes.destroy_all
      codes.each { |code| backup_codes.create!(code_digest: BCrypt::Password.create(code)) }
    end
    codes
  end

  def use_backup_code!(code)
    match = backup_codes.where(used_at: nil).find { |bc| BCrypt::Password.new(bc.code_digest) == code.to_s.strip.downcase }
    match ? match.update!(used_at: Time.current) : false
  end
end
