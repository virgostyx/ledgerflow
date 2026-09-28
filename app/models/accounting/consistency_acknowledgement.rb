class Accounting::ConsistencyAcknowledgement < ApplicationRecord
  self.table_name = "accounting_consistency_acknowledgements"

  acts_as_tenant :entity

  belongs_to :user, optional: true

  validates :fingerprint, presence: true, uniqueness: { scope: :entity_id }
  validates :comment, presence: true
end
