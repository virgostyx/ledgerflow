# F12a: a firm or a group that gathers entities, with the people who manage the gathering. Belonging to an organization gives access to nothing: what a
# person sees of an entity is still decided by their membership of that entity.
class Organization < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :organization_memberships, dependent: :destroy
  has_many :users, through: :organization_memberships
  has_many :entities, dependent: :nullify

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  def owner?(user) = organization_memberships.exists?(user_id: user.id, role: "owner")
end
