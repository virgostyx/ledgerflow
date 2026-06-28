class UserEntity < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  enum :role, { admin: 0, accountant: 1, manager: 2, auditor: 3 }

  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :entity_id, message: :taken }

  scope :active, -> { where(active: true) }
end
