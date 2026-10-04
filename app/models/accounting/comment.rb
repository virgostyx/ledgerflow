# A remark in the thread of a task or of a thing (F08). Never deleted: hidden, with a trace in the audit trail. Its author edits it for 15 minutes only.
# `mentioned_user_ids` are the people it names with @ and who may see what it is about.
class Accounting::Comment < ApplicationRecord
  include Accounting::AuditTrailed
  self.table_name = "accounting_comments"

  EDIT_WINDOW = 15.minutes

  acts_as_tenant :entity

  belongs_to :commentable, polymorphic: true
  belongs_to :parent, class_name: "Accounting::Comment", optional: true
  belongs_to :author, class_name: "User", optional: true
  belongs_to :resolved_by, class_name: "User", optional: true
  belongs_to :hidden_by, class_name: "User", optional: true
  has_many   :replies, -> { order(:id) }, class_name: "Accounting::Comment", foreign_key: :parent_id, inverse_of: :parent, dependent: :restrict_with_error

  validates :body, presence: true
  validates :commentable_type, inclusion: { in: Accounting::TaskTargets::TYPES + [ "Accounting::Task" ] }
  validate  :author_or_external

  before_destroy { raise Accounting::ImmutableRecordError, "A comment is hidden, never deleted" }

  scope :shown, -> { where(hidden_at: nil) }

  def hidden? = hidden_at.present?
  def resolved? = resolved_at.present?
  def editable_by?(user) = !hidden? && user && author_id == user.id && created_at > EDIT_WINDOW.ago

  # The thing the thread is finally about: a task is about its own target.
  def subject = commentable.is_a?(Accounting::Task) ? commentable.target : commentable

  private

  def author_or_external
    errors.add(:base, "A comment has an author or an external name") if author_id.nil? && external_name.blank?
  end
end
