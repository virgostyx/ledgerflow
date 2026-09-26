# One e-mail asking a customer to pay its overdue invoices (PDFs attached), at a level of firmness from 1 to 3.
# It covers several invoices, listed by its items; see Accounting::OverdueReminders and Accounting::SendPaymentReminders.
class Accounting::PaymentReminder < ApplicationRecord
  self.table_name = "accounting_payment_reminders"

  acts_as_tenant :entity

  enum :status, { queued: 0, sent: 1, failed: 2 }

  belongs_to :partner, class_name: "Accounting::Partner"
  belongs_to :sent_by, class_name: "User"
  has_many   :items, class_name: "Accounting::PaymentReminderItem", dependent: :destroy, inverse_of: :payment_reminder
  has_many   :invoices, through: :items

  validates :level,     inclusion: { in: 1..3 }
  validates :recipient, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  validates :subject,   presence: true
end
