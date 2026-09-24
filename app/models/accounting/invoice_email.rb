# One attempt to e-mail an invoice or credit note (PDF attached) to a recipient.
class Accounting::InvoiceEmail < ApplicationRecord
  self.table_name = "accounting_invoice_emails"

  acts_as_tenant :entity

  belongs_to :invoice, class_name: "Accounting::Invoice"
  belongs_to :sent_by, class_name: "User"

  enum :status, { queued: 0, sent: 1, failed: 2 }

  validates :recipient, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  validates :subject,   presence: true
end
