# A subject (a purchase invoice, later a payment batch) put to approval, on a given content: the fingerprint of what was
# submitted. A decision carries the fingerprint its author saw, so nobody approves a version they did not have in front of them.
class Approvals::Request < ApplicationRecord
  self.table_name = "approval_requests"

  acts_as_tenant :entity

  enum :status, { pending: 0, approved: 1, rejected: 2, changes_requested: 3, cancelled: 4, invalidated: 5 }

  belongs_to :policy, class_name: "Approvals::Policy", optional: true
  belongs_to :subject, polymorphic: true
  belongs_to :submitted_by, class_name: "User", optional: true
  has_many :decisions, -> { order(:decided_at, :id) }, class_name: "Approvals::Decision", foreign_key: :request_id, inverse_of: :request, dependent: :destroy

  validates :content_fingerprint, format: { with: /\A\h{64}\z/ }
  # The database has the same rule as a partial unique index; this gives the message before the insert.
  validate :only_one_pending_per_subject, if: :pending?

  private

  def only_one_pending_per_subject
    other = self.class.pending.where(subject_type: subject_type, subject_id: subject_id).where.not(id: id)
    errors.add(:subject, "is already waiting for an approval") if other.exists?
  end
end
