# One attempt to import a statement file (F02): who, which file (SHA-256), what came of it. A refused file leaves its batch
# (with the faulty lines), so that "why did my file not go in?" has an answer afterwards.
class Accounting::ImportBatch < ApplicationRecord
  self.table_name = "accounting_import_batches"

  # uploaded: a file waiting for its mapping (F13a); processing: queued or running in the background; undone: a guided import taken back
  RESULTS = %w[uploaded processing imported rejected undone].freeze

  acts_as_tenant :entity

  belongs_to :user, optional: true
  belongs_to :undone_by, class_name: "User", optional: true
  belongs_to :document, class_name: "Accounting::Document", optional: true
  has_one_attached :queued_file # the file waiting for its background import; gone once imported or refused
  has_many :statements, class_name: "Accounting::BankStatement", foreign_key: :import_batch_id, dependent: :restrict_with_error

  validates :parser, :file_sha256, presence: true
  validates :result, inclusion: { in: RESULTS }

  scope :guided, -> { where.not(kind: nil) } # F13a: the imports of partners, accounts and entries
  scope :imported, -> { where(result: "imported") }
end
