# What a person is told (F08): in the application and, when they asked for it, by e-mail. One per person, event and subject: a mention is never
# told twice.
class Accounting::Notification < ApplicationRecord
  self.table_name = "accounting_notifications"

  acts_as_tenant :entity

  enum :channel, { in_app: 0, email: 1 }

  belongs_to :user
  belongs_to :subject, polymorphic: true, optional: true

  validates :event, presence: true

  scope :unread, -> { where(read_at: nil) }

  def read! = (update!(read_at: Time.current) unless read_at)
end
