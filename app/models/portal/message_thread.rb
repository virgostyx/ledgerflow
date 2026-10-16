# B02c: the one thread of messages of a company between the people of its portal and the firm.
class Portal::MessageThread < ApplicationRecord
  self.table_name = "portal_threads"

  belongs_to :company, class_name: "Portal::Company", foreign_key: :entity_id, inverse_of: false
  has_many :messages, -> { order(:id) }, class_name: "Portal::Message", foreign_key: :thread_id, inverse_of: :thread

  has_secure_token :token

  # The thread of a company, made when it is first needed (two people at once make one: the entity is unique).
  def self.of(entity_id)
    find_by(entity_id: entity_id) || create!(entity_id: entity_id)
  rescue ActiveRecord::RecordNotUnique
    find_by!(entity_id: entity_id)
  end
end
