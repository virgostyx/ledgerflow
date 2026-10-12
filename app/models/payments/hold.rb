# A hold on an invoice or on a whole supplier (B01b): nothing is paid while it lasts. Lifted by a person, who is recorded.
class Payments::Hold < ApplicationRecord
  self.table_name = "payment_holds"

  acts_as_tenant :entity

  belongs_to :invoice, class_name: "Accounting::Invoice", optional: true
  belongs_to :partner, class_name: "Accounting::Partner", optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :released_by, class_name: "User", optional: true

  validates :reason, presence: true
  validate :something_held

  scope :active, -> { where(released_at: nil) }

  def active? = released_at.nil?

  private

  def something_held = (errors.add(:base, "an invoice or a supplier must be held") if invoice_id.nil? && partner_id.nil? && invoice.nil? && partner.nil?)
end
