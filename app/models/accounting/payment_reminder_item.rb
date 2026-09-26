# An invoice covered by a payment reminder, with the amount still due on it when the reminder was made.
class Accounting::PaymentReminderItem < ApplicationRecord
  self.table_name = "accounting_payment_reminder_items"

  acts_as_tenant :entity

  belongs_to :payment_reminder, class_name: "Accounting::PaymentReminder", inverse_of: :items
  belongs_to :invoice, class_name: "Accounting::Invoice"

  validates :amount_due, presence: true
end
