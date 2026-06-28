class AddEntityIdToAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_audit_logs, :entity_id, :bigint
    add_index :accounting_audit_logs, %i[entity_id created_at],
              name: "index_accounting_audit_logs_on_entity_id_and_created_at"
  end
end
