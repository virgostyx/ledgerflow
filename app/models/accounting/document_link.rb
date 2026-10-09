# A document attached to something it justifies (F03). A document may have several targets and a target several documents.
class Accounting::DocumentLink < ApplicationRecord
  self.table_name = "accounting_document_links"

  TARGET_TYPES = %w[Accounting::JournalEntry Accounting::Partner Accounting::FixedAsset Accounting::Invoice Accounting::BankTransaction Accounting::BankStatement].freeze

  belongs_to :document, class_name: "Accounting::Document", inverse_of: :links
  belongs_to :target, polymorphic: true
  belongs_to :created_by, class_name: "User", optional: true

  after_commit :sync_approval, if: -> { target_type == "Accounting::Invoice" } # B01a: a document is part of what is approved

  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :target_id, uniqueness: { scope: %i[document_id target_type] }

  private

  def sync_approval
    invoice = Accounting::Invoice.find_by(id: target_id)
    Approvals::Sync.call(invoice) if invoice
  end
end
