# Something left to do about an entry, a ledger line, an account, a partner, a document, a bank line or a period (F08), or about an anomaly of the
# consistency checks (R19). Written about, never touching what it is about: a task on a validated entry changes nothing in it.
class Accounting::Task < ApplicationRecord
  include Accounting::AuditTrailed
  self.table_name = "accounting_tasks"

  acts_as_tenant :entity

  enum :status,   { open: 0, in_progress: 1, blocked: 2, done: 3, cancelled: 4 }
  enum :priority, { low: 0, normal: 1, high: 2 }
  enum :kind,     { missing_document: 0, to_check: 1, client_question: 2, closing: 3, other: 4 }

  belongs_to :target, polymorphic: true, optional: true
  belongs_to :assignee,     class_name: "User", optional: true
  belongs_to :author,       class_name: "User", optional: true
  belongs_to :completed_by, class_name: "User", optional: true
  has_many   :comments, -> { order(:id) }, as: :commentable, class_name: "Accounting::Comment", dependent: :restrict_with_error

  validates :title, presence: true
  validates :target_type, inclusion: { in: Accounting::TaskTargets::TYPES }, allow_nil: true
  validate  :target_in_the_entity
  validate  :assignee_is_a_member

  CLOSED = %w[done cancelled].freeze
  EXTERNAL_PURPOSE = :external_reply

  # The link a third party answers a question through: a signed id that ends when the task says (revoked when `external_expires_at` is cleared).
  def external_link_token = (signed_id(purpose: EXTERNAL_PURPOSE, expires_at: external_expires_at) if external_open?)

  def external_open? = question.present? && external_expires_at.present? && external_expires_at > Time.current

  # The task a link opens, or nil: the signature, the date in it, and the date the task still holds must all agree. Outside any tenant (a public page).
  def self.find_by_external_token(token)
    task = ActsAsTenant.without_tenant { find_signed(token.to_s, purpose: EXTERNAL_PURPOSE) }
    task if task&.external_open?
  end

  scope :open_ones, -> { where.not(status: CLOSED) }
  scope :overdue, -> { open_ones.where("due_on < ?", Date.current) }
  scope :about, ->(target) { where(target_type: target.class.name, target_id: target.id) }

  def closed? = CLOSED.include?(status)

  # The tasks a user may see: those about what they may see (the lines of an entry are seen like the entry), and the ones about nothing when they
  # wrote them, are assigned them, or may manage tasks.
  def self.visible_to(user)
    types = Accounting::TaskTargets.visible_types(user)
    membership = UserEntity.current.find_by(user: user, entity: ActsAsTenant.current_tenant)
    visible = where(target_type: types - %w[Accounting::JournalEntry Accounting::JournalEntryLine])
    if types.intersect?(%w[Accounting::JournalEntry Accounting::JournalEntryLine])
      visible = visible.or(where(target_type: "Accounting::JournalEntry").where(target_id: entries_visible_to(membership).select(:id)))
                       .or(where(target_type: "Accounting::JournalEntryLine").where(target_id: Accounting::JournalEntryLine.where(journal_entry_id: entries_visible_to(membership).select(:id)).select(:id)))
    end
    visible.or(where(target_type: nil).where("author_id = :u OR assignee_id = :u OR :manage", u: user.id, manage: membership&.allows?("tasks.manage") == true))
  end

  def self.entries_visible_to(membership)
    ids = membership&.journal_ids
    ids.present? ? Accounting::JournalEntry.where(journal_id: ids) : Accounting::JournalEntry.all
  end
  private_class_method :entries_visible_to

  private

  def target_in_the_entity
    errors.add(:target, "does not belong to this entity") if target && target.respond_to?(:entity_id) && target.entity_id != entity_id
  end

  def assignee_is_a_member
    return unless assignee_id && (new_record? || will_save_change_to_assignee_id?)

    errors.add(:assignee, "has no access to this entity") unless UserEntity.current.exists?(user_id: assignee_id, entity_id: entity_id)
  end
end
