# F03: why a document is under legal hold (a hold needs a reason, which is audited).
class AddLegalHoldReasonToAccountingDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_documents, :legal_hold_reason, :text
  end
end
