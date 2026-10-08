# A fact about a case that a person wrote, or confirmed after the agent proposed it (A10b): "this customer always pays at 45 days". The agent reads it, quotes it as a note and never takes a figure from it.
# Never created by the agent itself; everything it keeps is here, visible, editable, deletable for good. Not verified by the books, and treated as data that may hold an instruction.
class Agent::MemoryNote < ApplicationRecord
  self.table_name = "agent_memory_notes"

  SCOPES = %w[entity partner account].freeze
  CATEGORIES = %w[convention partner deadline reminder other].freeze
  STATUSES = %w[active archived].freeze
  MAX_LENGTH = 500
  UNUSED_MONTHS = 12

  acts_as_tenant :entity

  belongs_to :author, class_name: "User"

  encrypts :text

  validates :text, presence: true, length: { maximum: MAX_LENGTH }
  validates :scope_kind, inclusion: { in: SCOPES }
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :scope_id, presence: true, unless: -> { scope_kind == "entity" }
  validate :object_exists

  scope :active, -> { where(status: "active").where("valid_until IS NULL OR valid_until >= ?", Date.current) }
  scope :for_scope, ->(kind, id) { where(scope_kind: kind, scope_id: id) }
  scope :ordered, -> { order(created_at: :desc, id: :desc) }
  scope :expired, -> { where(status: "active").where("valid_until < ?", Date.current) }
  scope :unused, -> { where(status: "active").where("COALESCE(last_used_at, created_at) < ?", UNUSED_MONTHS.months.ago) }

  # The object the note is about, or nil: for a note on the whole file, or an object that was deleted.
  def object
    case scope_kind
    when "partner" then Accounting::Partner.find_by(id: scope_id)
    when "account" then Accounting::Account.find_by(id: scope_id)
    end
  end

  def object_missing? = scope_kind != "entity" && object.nil?
  def label = scope_kind == "entity" ? "The whole file" : "#{scope_kind.capitalize} ##{scope_id}"
  def active? = status == "active" && (valid_until.nil? || valid_until >= Date.current)

  # Told by the agent tool when it quotes the note: counts a use, which the screen shows and which keeps a note from being proposed for archiving.
  def self.used!(ids) = where(id: ids).update_all("uses_count = uses_count + 1, last_used_at = '#{Time.current.utc.iso8601}'")

  # The notes that go with the deadline or the age: archived by themselves (the date passed).
  def self.archive_expired! = expired.update_all(status: "archived", updated_at: Time.current)

  private

  def object_exists
    return if scope_kind == "entity" || scope_id.blank?

    errors.add(:scope_id, "is not an object of this entity") unless object
  end
end
