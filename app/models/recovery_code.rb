class RecoveryCode < ApplicationRecord
  belongs_to :user

  # passkey: last resort of a passwordless user who lost the passkey. totp: one-time backup codes of the second factor.
  enum :kind, { passkey: "passkey", totp: "totp" }

  scope :unused, -> { where(used_at: nil) }
end
