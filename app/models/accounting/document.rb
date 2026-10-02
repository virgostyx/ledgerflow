# A supporting document (F03): an invoice, a statement, a contract... The file is never modified (a new version is a
# new document pointing to the old one) and is kept for `RETENTION_YEARS` years. Linked to a validated entry, a
# document can only be archived.
class Accounting::Document < ApplicationRecord
  self.table_name = "accounting_documents"

  # To be confirmed with the accounting regulations in force (docs/dev/features/QUESTIONS.md).
  RETENTION_YEARS = 10

  acts_as_tenant :entity

  enum :origin, { manual_upload: 0, email: 1, peppol: 2, bank_import: 3, scan: 4 }
  enum :kind,   { other: 0, purchase_invoice: 1, sales_invoice: 2, credit_note: 3, statement: 4, contract: 5 }
  enum :status, { inbox: 0, linked: 1, archived: 2 }

  has_one_attached :file
  belongs_to :uploaded_by, class_name: "User", optional: true
  belongs_to :replaces, class_name: "Accounting::Document", optional: true

  attr_readonly :sha256, :byte_size

  validates :name, :byte_size, presence: true
  validates :sha256, presence: true, uniqueness: { scope: :entity_id }
  validate  :file_attached
  validate  :file_not_replaced, on: :update

  before_validation :set_retention, on: :create
  before_update :refuse_change_when_locked
  # Declared before the links so that a refused deletion leaves them alone.
  before_destroy :refuse_early_deletion
  has_many :links, class_name: "Accounting::DocumentLink", foreign_key: :document_id, inverse_of: :document, dependent: :destroy

  # Linked to a validated entry: the document is evidence and can only be archived.
  def locked?
    entry_ids = links.where(target_type: "Accounting::JournalEntry").select(:target_id)
    Accounting::JournalEntry.where(id: entry_ids).where.not(status: :draft).exists?
  end

  # Only after the retention term, and never under a legal hold.
  def deletable? = !legal_hold && retention_until.present? && retention_until <= Date.current

  private

  def set_retention = self.retention_until ||= Date.current + RETENTION_YEARS.years

  def file_attached
    errors.add(:file, :blank) unless file.attached?
  end

  def file_not_replaced
    errors.add(:file, "cannot be replaced: upload a new document instead") if attachment_changes["file"].present?
  end

  # Once linked to a validated entry only the status may move (to archive it).
  def refuse_change_when_locked
    return unless locked?
    return if (changes_to_save.keys - %w[status updated_at]).empty?

    raise Accounting::ImmutableRecordError, "Document ##{id} is linked to a validated entry: it can only be archived."
  end

  def refuse_early_deletion
    return if deletable?

    errors.add(:base, legal_hold ? "A document under legal hold cannot be deleted." : "A document is kept until the end of its retention period.")
    throw :abort
  end
end
