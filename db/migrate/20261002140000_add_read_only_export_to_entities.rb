# F01: whether the read-only roles (reader, external auditor) may export. Off unless the owner allows it.
class AddReadOnlyExportToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :read_only_export, :boolean, null: false, default: false
  end
end
