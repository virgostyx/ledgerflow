# F03: a document cut out of another one (one invoice of a scan holding several). The parent is never modified.
class AddParentToAccountingDocuments < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounting_documents, :parent, foreign_key: { to_table: :accounting_documents, on_delete: :nullify }
  end
end
