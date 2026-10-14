# B03a: the reference data as it was at an instant. A version of an account (code, labels, class, type, balance side, currency) or of a partner (name, VAT number, type) is
# written by the database each time one of those changes; nothing else (the cached balances move with every validation). What exists already gets a first version, dated when
# it was created, with what it holds now: the former names of what was renamed before are not known.
# Tax codes and the headings of the statements are not versioned yet (see QUESTIONS.md).
class CreateMasterDataVersions < ActiveRecord::Migration[8.1]
  ACCOUNT_ATTRS = "jsonb_build_object('code', NEW.code, 'label_fr', NEW.label_fr, 'label_nl', NEW.label_nl, 'account_class', NEW.account_class, 'account_type', NEW.account_type, " \
                  "'normal_balance', NEW.normal_balance, 'currency', NEW.currency)".freeze
  PARTNER_ATTRS = "jsonb_build_object('name', NEW.name, 'vat_number', NEW.vat_number, 'partner_type', NEW.partner_type)".freeze

  def up
    create_table :accounting_master_data_versions do |t|
      t.bigint :entity_id, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.jsonb :attrs, null: false
      t.datetime :valid_from, null: false, precision: 6
    end
    add_index :accounting_master_data_versions, %i[record_type record_id valid_from], name: "index_master_data_versions_on_record_and_instant"
    add_index :accounting_master_data_versions, :entity_id

    version_function("accounts", "Accounting::Account", ACCOUNT_ATTRS, "TG_OP = 'INSERT' OR NEW.code IS DISTINCT FROM OLD.code OR NEW.label_fr IS DISTINCT FROM OLD.label_fr OR NEW.label_nl IS DISTINCT FROM OLD.label_nl OR " \
                    "NEW.account_class IS DISTINCT FROM OLD.account_class OR NEW.account_type IS DISTINCT FROM OLD.account_type OR NEW.normal_balance IS DISTINCT FROM OLD.normal_balance OR NEW.currency IS DISTINCT FROM OLD.currency")
    version_function("partners", "Accounting::Partner", PARTNER_ATTRS, "TG_OP = 'INSERT' OR NEW.name IS DISTINCT FROM OLD.name OR NEW.vat_number IS DISTINCT FROM OLD.vat_number OR NEW.partner_type IS DISTINCT FROM OLD.partner_type")

    execute <<~SQL
      INSERT INTO accounting_master_data_versions (entity_id, record_type, record_id, attrs, valid_from)
      SELECT entity_id, 'Accounting::Account', id,
             jsonb_build_object('code', code, 'label_fr', label_fr, 'label_nl', label_nl, 'account_class', account_class, 'account_type', account_type, 'normal_balance', normal_balance, 'currency', currency),
             created_at FROM accounting_accounts
    SQL
    execute <<~SQL
      INSERT INTO accounting_master_data_versions (entity_id, record_type, record_id, attrs, valid_from)
      SELECT entity_id, 'Accounting::Partner', id, jsonb_build_object('name', name, 'vat_number', vat_number, 'partner_type', partner_type), created_at FROM accounting_partners
    SQL

    execute <<~SQL
      CREATE FUNCTION prevent_master_data_version_change() RETURNS trigger
          LANGUAGE plpgsql
          AS $$
      BEGIN
        RAISE EXCEPTION 'a version of the reference data is never changed' USING ERRCODE = 'raise_exception';
      END;
      $$;
    SQL
    execute "CREATE TRIGGER prevent_master_data_version_change BEFORE UPDATE OR DELETE ON accounting_master_data_versions FOR EACH ROW EXECUTE FUNCTION prevent_master_data_version_change()"
  end

  def down
    execute "DROP TRIGGER prevent_master_data_version_change ON accounting_master_data_versions"
    execute "DROP FUNCTION prevent_master_data_version_change()"
    %w[accounts partners].each do |table|
      execute "DROP TRIGGER version_#{table} ON accounting_#{table}"
      execute "DROP FUNCTION version_#{table}()"
    end
    drop_table :accounting_master_data_versions
  end

  private

  def version_function(table, type, attrs, changed)
    execute <<~SQL
      CREATE FUNCTION version_#{table}() RETURNS trigger
          LANGUAGE plpgsql
          AS $$
      BEGIN
        IF #{changed} THEN
          INSERT INTO accounting_master_data_versions (entity_id, record_type, record_id, attrs, valid_from)
          VALUES (NEW.entity_id, '#{type}', NEW.id, #{attrs}, clock_timestamp() AT TIME ZONE 'UTC');
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
    execute "CREATE TRIGGER version_#{table} AFTER INSERT OR UPDATE ON accounting_#{table} FOR EACH ROW EXECUTE FUNCTION version_#{table}()"
  end
end
