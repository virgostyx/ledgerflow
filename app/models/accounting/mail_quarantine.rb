# B02b: a mail to the documents address that was not taken in (a stranger, or an authentication the server did not vouch for), kept as it came and unread until a person of the firm looks at it.
# The raw message is never parsed here: only a release hands its attachments to the usual upload (antivirus, integrity, duplicates).
class Accounting::MailQuarantine < ApplicationRecord
  self.table_name = "accounting_mail_quarantines"

  REASONS = %w[sender_not_allowed authentication_failed].freeze

  acts_as_tenant :entity

  belongs_to :reviewed_by, class_name: "User", optional: true
  enum :status, { pending: "pending", released: "released", discarded: "discarded" }, default: "pending"

  validates :reason, inclusion: { in: REASONS }
  validates :raw, presence: true
end
