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

  validates :full_name, presence: true
  validates :email,     presence: true

  scope :active, -> { where(active: true) }

  def active_for_authentication?
    super && active?
  end

  def inactive_message
    active? ? super : :inactive_account
  end

  def can_post_entries?
    admin? || accountant?
  end

  def can_manage_invoices?
    admin? || accountant? || manager?
  end
end
