# Signature functions (B02a): the portal's people are not users, so a row of the audit chain says what kind of actor wrote it.
# A constant default adds the column without touching a single row, so the immutability trigger and the chain already
# written are left alone; a row by a user hashes as before (see AuditLog.digest). Reversible.
class AddActorTypeToAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_audit_logs, :actor_type, :string, null: false, default: "user"
  end
end
