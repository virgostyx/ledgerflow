# R18 (docs/dev/reports/spec.md §13): tamper-evident chain and request context on the append-only audit log.
# Rows written before this migration keep NULL hashes (the table is immutable, they cannot be backfilled);
# the chain of an entity starts at its first hashed row.
class AddIntegrityChainToAccountingAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_audit_logs, :previous_hash, :string
    add_column :accounting_audit_logs, :content_hash, :string
    add_column :accounting_audit_logs, :reason, :text
    add_column :accounting_audit_logs, :user_agent, :string
    add_column :accounting_audit_logs, :request_id, :string
    add_index :accounting_audit_logs, [ :entity_id, :id ], name: "index_accounting_audit_logs_on_entity_and_id"
    add_index :accounting_audit_logs, :request_id
  end
end
