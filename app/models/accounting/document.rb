# A supporting document (F03): an invoice, a statement, a contract... The file is never modified (a new version is a
# new document pointing to the old one) and is kept for `RETENTION_YEARS` years. Linked to a validated entry, a
# document can only be archived.
class Accounting::Document < ApplicationRecord
  self.table_name = "accounting_documents"

  # To be confirmed with the accounting regulations in force (docs/dev/features/QUESTIONS.md). Per kind of document,
  # ten years unless a kind is given its own term here.
  RETENTION_YEARS = 10
  RETENTION_YEARS_BY_KIND = Hash.new(RETENTION_YEARS)

  acts_as_tenant :entity

  enum :origin, { manual_upload: 0, email: 1, peppol: 2, bank_import: 3, scan: 4, external_reply: 5 }
  enum :kind,   { other: 0, purchase_invoice: 1, sales_invoice: 2, credit_note: 3, statement: 4, contract: 5 }
  enum :status, { inbox: 0, linked: 1, archived: 2 }

  has_one_attached :file
  belongs_to :uploaded_by, class_name: "User", optional: true
  belongs_to :replaces, class_name: "Accounting::Document", optional: true
  # The document this one was cut out of (a scan holding several invoices); the parent is never modified.
  belongs_to :parent, class_name: "Accounting::Document", optional: true
  has_many :children, class_name: "Accounting::Document", foreign_key: :parent_id, inverse_of: :parent, dependent: :nullify

  attr_readonly :sha256, :byte_size

  after_create_commit do # F13c
    Webhooks::Emit.call("document.created", { id: id, name: name, kind: kind, origin: origin, sha256: sha256 }, entity: entity)
  end

  validates :name, :byte_size, presence: true
  validates :sha256, presence: true, uniqueness: { scope: :entity_id }
  validates :legal_hold_reason, presence: true, if: :legal_hold
  validate  :file_attached
  validate  :file_not_replaced, on: :update

  before_validation :set_retention, on: :create
  before_update :extend_retention_for_kind, if: :will_save_change_to_kind?
  before_update :refuse_change_when_locked
  # Declared before the links so that a refused deletion leaves them alone.
  before_destroy :refuse_early_deletion
  has_many :links, class_name: "Accounting::DocumentLink", foreign_key: :document_id, inverse_of: :document, dependent: :destroy

  # Every word must be found (in any order), anywhere in the name, the text read or the values read; accents and case
  # do not matter. Words are matched as substrings through the trigram index on `search_blob`.
  MAX_SEARCH_WORDS = 8

  scope :search, lambda { |query|
    query.to_s.split(/\s+/).reject(&:blank?).first(MAX_SEARCH_WORDS).inject(all) do |scope, word|
      scope.where("search_blob LIKE '%' || lower(f_unaccent(?)) || '%'", sanitize_sql_like(word))
    end
  }

  # Documents about a partner: linked to them, naming them (the supplier read from the document), or linked to one of
  # their invoices.
  scope :for_partner, lambda { |partner_id|
    where(<<~SQL.squish, partner_id, partner_id.to_s, partner_id)
      accounting_documents.id IN (SELECT document_id FROM accounting_document_links WHERE target_type = 'Accounting::Partner' AND target_id = ?)
      OR (accounting_documents.extracted_data #>> '{extraction,fields,supplier_partner_id,value}') = ?
      OR accounting_documents.id IN (SELECT l.document_id FROM accounting_document_links l
                                     JOIN accounting_invoices i ON i.id = l.target_id AND l.target_type = 'Accounting::Invoice' WHERE i.partner_id = ?)
    SQL
  }

  # The date of the document: the invoice date read from it, else the day it was uploaded.
  DATE_SQL = <<~'SQL'.squish.freeze
    COALESCE(CASE WHEN (accounting_documents.extracted_data #>> '{extraction,fields,invoice_date,value}') ~ '^\d{4}-\d{2}-\d{2}$'
                  THEN (accounting_documents.extracted_data #>> '{extraction,fields,invoice_date,value}')::date END,
             accounting_documents.created_at::date)
  SQL
  scope :dated, lambda { |from, to|
    scope = all
    scope = scope.where("#{DATE_SQL} >= ?", from) if from
    scope = scope.where("#{DATE_SQL} <= ?", to) if to
    scope
  }

  # The total read from the document (a value that is not a number never matches).
  AMOUNT_SQL = <<~'SQL'.squish.freeze
    CASE WHEN (accounting_documents.extracted_data #>> '{extraction,fields,total,value}') ~ '^-{0,1}\d+(\.\d+){0,1}$'
         THEN (accounting_documents.extracted_data #>> '{extraction,fields,total,value}')::numeric END
  SQL
  scope :amount_between, lambda { |min, max|
    scope = all
    scope = scope.where("#{AMOUNT_SQL} >= ?", min) if min
    scope = scope.where("#{AMOUNT_SQL} <= ?", max) if max
    scope
  }

  # The number of pages of a PDF, as read at upload (read from the file for a document stored before that).
  def page_count
    return unless content_type == "application/pdf" && !extracted_data["unreadable"]

    extracted_data["pages"] || PDF::Reader.new(StringIO.new(file.download)).page_count
  rescue StandardError
    nil
  end

  # Linked to a validated entry: the document is evidence and can only be archived.
  def locked?
    entry_ids = links.where(target_type: "Accounting::JournalEntry").select(:target_id)
    Accounting::JournalEntry.where(id: entry_ids).where.not(status: :draft).exists?
  end

  # Only after the retention term, and never under a legal hold.
  def deletable? = !legal_hold && retention_until.present? && retention_until <= Date.current

  private

  def set_retention = self.retention_until ||= Date.current + RETENTION_YEARS_BY_KIND[kind].years

  # A change of kind can lengthen the term, never shorten it.
  def extend_retention_for_kind
    self.retention_until = [ retention_until, created_at.to_date + RETENTION_YEARS_BY_KIND[kind].years ].compact.max
  end

  def file_attached
    errors.add(:file, :blank) unless file.attached?
  end

  def file_not_replaced
    errors.add(:file, "cannot be replaced: upload a new document instead") if attachment_changes["file"].present?
  end

  # Once linked to a validated entry only the status may move (to archive it).
  def refuse_change_when_locked
    return unless locked?
    return if (changes_to_save.keys - %w[status updated_at legal_hold legal_hold_reason]).empty? # retention controls leave the evidence alone

    raise Accounting::ImmutableRecordError, "Document ##{id} is linked to a validated entry: it can only be archived."
  end

  def refuse_early_deletion
    return if deletable?

    errors.add(:base, legal_hold ? "A document under legal hold cannot be deleted." : "A document is kept until the end of its retention period.")
    throw :abort
  end
end
