# B03b: what a person wants to be told of the changes (kinds of alerts), and when they were last told: one notification a day at most.
class Accounting::ChangeSubscription < ApplicationRecord
  self.table_name = "accounting_change_subscriptions"

  KINDS = %w[late locked_period iban_change].freeze

  acts_as_tenant :entity

  belongs_to :user

  validates :kinds, length: { minimum: 1 }
  validate { errors.add(:kinds, :invalid) unless (kinds - KINDS).empty? }
end
