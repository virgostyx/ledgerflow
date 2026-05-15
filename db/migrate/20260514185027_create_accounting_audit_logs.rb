class CreateAccountingAuditLogs < ActiveRecord::Migration[8.1]
  def up
    create_table :accounting_audit_logs do |t|
      t.string   :auditable_type,  null: false
      t.bigint   :auditable_id,    null: false
      t.string   :action,          null: false
      t.bigint   :user_id
      t.string   :user_email
      t.jsonb    :payload,         default: {}
      t.string   :ip_address
      t.timestamps
    end

    add_index :accounting_audit_logs, [ :auditable_type, :auditable_id ]
    add_index :accounting_audit_logs, :user_id
    add_index :accounting_audit_logs, :action
    add_index :accounting_audit_logs, :created_at

    # Trigger blocks UPDATE and DELETE for all users, including the table owner
    execute <<~SQL
      CREATE OR REPLACE FUNCTION prevent_audit_log_modification()
      RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'accounting_audit_logs are immutable';
      END;
      $$;

      CREATE TRIGGER enforce_audit_log_immutability
      BEFORE UPDATE OR DELETE ON accounting_audit_logs
      FOR EACH ROW EXECUTE FUNCTION prevent_audit_log_modification();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS enforce_audit_log_immutability ON accounting_audit_logs;"
    execute "DROP FUNCTION IF EXISTS prevent_audit_log_modification();"
    drop_table :accounting_audit_logs
  end
end
