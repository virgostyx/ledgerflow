# B02b: a request of the firm to a client for the supporting documents of some bank lines. Written by the firm; the portal only reads it.
class Portal::DocumentRequest < ApplicationRecord
  belongs_to :company, class_name: "Portal::Company", foreign_key: :entity_id, inverse_of: false
  belongs_to :requested_by, class_name: "User"
  has_many :lines, class_name: "Portal::DocumentRequestLine", foreign_key: :request_id, inverse_of: :request

  has_secure_token :token

  def to_param = token
end
