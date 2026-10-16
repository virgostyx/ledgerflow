# B02c: a message in the thread of a company, from a person of the portal or from the firm. Never edited, never deleted. A message is not an accounting instruction nor a formal agreement
# (the screens say so). The text of a client is untrusted: cleaned and limited.
class Portal::Message < ApplicationRecord
  MAX_BODY = 2_000
  PER_DAY = 50

  belongs_to :thread, class_name: "Portal::MessageThread", inverse_of: :messages
  belongs_to :portal_user, optional: true

  validates :body, presence: true, length: { maximum: MAX_BODY }
  validates :author_kind, inclusion: { in: %w[client firm] }

  scope :by_clients, -> { where(author_kind: "client") }

  # The text of a message of a client: no tag, no control character.
  def self.clean(text) = Portal::Answer.clean(text).first(MAX_BODY)

  def self.written_today_by(person) = where(portal_user_id: person.id, created_at: 24.hours.ago..).count

  before_update { raise ActiveRecord::ReadOnlyRecord, "a message is never edited" unless only_firm_marks_changed? }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "a message is never deleted" }

  private

  # Only the firm's own marks may change: the task a message became, and that it was read.
  def only_firm_marks_changed? = (changed - %w[task_id read_by_firm_at updated_at]).empty?
end
