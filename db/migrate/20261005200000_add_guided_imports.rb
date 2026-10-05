# F13a: guided imports. The batch of F02 (accounting_import_batches) is reused for the file, its mapping and what came of it;
# each object a batch creates carries `import_batch_id`, and an entry carries the piece key of the file as `external_id` (no duplicate on a re-run).
class AddGuidedImports < ActiveRecord::Migration[8.1]
  def change
    change_table :accounting_import_batches do |t|
      t.string :kind                        # partners / accounts / entries; nil for a bank statement batch
      t.string :filename
      t.jsonb  :mapping,  null: false, default: {}
      t.jsonb  :options,  null: false, default: {}
      t.jsonb  :summary,  null: false, default: {}
      t.string :undo_reason
      t.references :undone_by, foreign_key: { to_table: :users }
      t.datetime :undone_at
    end

    create_table :import_templates do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.jsonb  :mapping, null: false, default: {}
      t.jsonb  :options, null: false, default: {}
      t.timestamps
    end
    add_index :import_templates, %i[entity_id kind name], unique: true

    %i[accounting_partners accounting_accounts accounting_journal_entries].each do |table|
      add_reference table, :import_batch, foreign_key: { to_table: :accounting_import_batches }
    end
    add_column :accounting_journal_entries, :external_id, :string
    add_index :accounting_journal_entries, %i[entity_id external_id], unique: true, where: "external_id IS NOT NULL", name: "idx_entries_external_id"
  end
end
