# A document injected by a third party is identified by its external_ref; a correction is a new revision of
# the same reference (the previous document is reversed). external_digest detects an identical replay and marks
# the documents managed through the API: the free-text external_ref typed in the UI (a supplier's own invoice
# number) is not unique and must stay outside this key.
class AddExternalRevisionToAccountingInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_invoices, :revision, :integer, null: false, default: 1
    add_column :accounting_invoices, :external_digest, :string
    add_index :accounting_invoices, [ :entity_id, :external_ref, :revision ], unique: true,
              where: "external_digest IS NOT NULL", name: "index_accounting_invoices_on_entity_ref_revision"
  end
end
