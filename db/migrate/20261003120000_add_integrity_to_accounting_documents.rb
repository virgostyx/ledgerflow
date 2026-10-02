# F03: the result of the weekly check that the stored file still is what was stored (SHA-256 recomputed).
class AddIntegrityToAccountingDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_documents, :integrity_status, :string # ok, mismatch, missing; nil until checked
    add_column :accounting_documents, :integrity_checked_at, :datetime
    add_index :accounting_documents, :integrity_status, where: "integrity_status IN ('mismatch', 'missing')", name: "idx_documents_integrity_failed"
  end
end
