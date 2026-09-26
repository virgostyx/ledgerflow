class RecoveryCode < ApplicationRecord
  belongs_to :user

  scope :unused, -> { where(used_at: nil) }
end
