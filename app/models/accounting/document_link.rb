# A document attached to something it justifies (F03). A document may have several targets and a target several documents.
class Accounting::DocumentLink < ApplicationRecord
  self.table_name = "accounting_document_links"

  TARGET_TYPES = %w[Accounting::JournalEntry Accounting::Partner Accounting::FixedAsset Accounting::Invoice Accounting::BankTransaction].freeze

  belongs_to :document, class_name: "Accounting::Document", inverse_of: :links
  belongs_to :target, polymorphic: true
  belongs_to :created_by, class_name: "User", optional: true

  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :target_id, uniqueness: { scope: %i[document_id target_type] }
end
