# A director's request that the firm give someone access. It changes nothing by itself.
class Portal::AccessRequest < ApplicationRecord
  belongs_to :company, class_name: "Portal::Company", foreign_key: :entity_id, inverse_of: false
  belongs_to :requested_by, class_name: "PortalUser"
  belongs_to :decided_by, class_name: "User", optional: true

  enum :status, { pending: "pending", granted: "granted", declined: "declined" }, default: "pending"

  validates :role, inclusion: { in: Portal::ROLES }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :full_name, presence: true, length: { maximum: 120 }
  validates :note, length: { maximum: 500 }, allow_blank: true
end
