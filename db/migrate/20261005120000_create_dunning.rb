# F09: customer dunning. The policy (levels, texts, threshold, optional charges) is one row per entity; a run is one preparation; an item is one
# customer in a run, with the open ledger lines it covers (and their residual when it was prepared). The lines carry what decides whether they are
# proposed (disputed, promised date) and the last level sent. Those four columns do not change an amount, so the period lock lets them through.
class CreateDunning < ActiveRecord::Migration[8.1]
  LOCK_FUNCTION = <<~SQL.freeze
    CREATE OR REPLACE FUNCTION enforce_period_lock_on_lines() RETURNS trigger
        LANGUAGE plpgsql
        AS $$
    BEGIN
      IF current_setting('ledgerflow.lock_override', true) = 'on' THEN
        RETURN COALESCE(NEW, OLD);
      END IF;
      -- lettering and dunning follow-up stay possible in a locked period: only these columns may change
      IF TG_OP = 'UPDATE' AND NEW.journal_entry_id = OLD.journal_entry_id
         AND (to_jsonb(NEW) - ARRAY[%<columns>s])
           = (to_jsonb(OLD) - ARRAY[%<columns>s]) THEN
        RETURN NEW;
      END IF;
      IF TG_OP IN ('UPDATE', 'DELETE') AND entry_in_locked_period(OLD.journal_entry_id) THEN
        RAISE EXCEPTION 'line %% belongs to a validated entry of a locked period', OLD.id USING ERRCODE = 'raise_exception';
      END IF;
      IF TG_OP IN ('INSERT', 'UPDATE') AND entry_in_locked_period(NEW.journal_entry_id) THEN
        RAISE EXCEPTION 'a line cannot be added to a validated entry of a locked period' USING ERRCODE = 'raise_exception';
      END IF;
      RETURN COALESCE(NEW, OLD);
    END;
    $$;
  SQL
  BEFORE = "'lettering_id', 'amount_residual', 'updated_at'".freeze
  AFTER  = "#{BEFORE}, 'disputed', 'payment_promised_on', 'dunning_level', 'last_dunned_at'".freeze

  def up
    add_column :accounting_journal_entry_lines, :disputed, :boolean, null: false, default: false
    add_column :accounting_journal_entry_lines, :payment_promised_on, :date
    add_column :accounting_journal_entry_lines, :dunning_level, :integer, null: false, default: 0
    add_column :accounting_journal_entry_lines, :last_dunned_at, :datetime
    add_column :accounting_partners, :do_not_dun, :boolean, null: false, default: false
    add_column :accounting_partners, :email_bounced_at, :datetime
    add_column :accounting_partners, :language, :string, null: false, default: "fr"
    execute format(LOCK_FUNCTION, columns: AFTER)

    create_table :dunning_policies do |t|
      t.references :entity, null: false, foreign_key: true, index: { unique: true }
      t.integer :level_1_days, null: false, default: 7
      t.integer :level_2_days, null: false, default: 21
      t.integer :level_3_days, null: false, default: 45
      t.decimal :min_amount, precision: 15, scale: 2, null: false, default: 0
      t.integer :follow_up_days, null: false, default: 7
      t.integer :min_days_between, null: false, default: 14               # a line reminded is not asked for again before this many days
      t.decimal :fee_1, precision: 15, scale: 2, null: false, default: 0   # optional charge per level, 0 = none
      t.decimal :fee_2, precision: 15, scale: 2, null: false, default: 0
      t.decimal :fee_3, precision: 15, scale: 2, null: false, default: 0
      t.boolean :interest_enabled, null: false, default: false
      t.decimal :interest_rate, precision: 7, scale: 3                     # yearly %, typed by the accountant, never defaulted
      t.boolean :indemnity_enabled, null: false, default: false
      t.decimal :indemnity_amount, precision: 15, scale: 2
      t.boolean :auto_send_level_1, null: false, default: false
      t.string  :from_name
      t.string  :reply_to                                                   # where the answers go (the sending address is the application's, SPF/DKIM are its domain's)
      t.text    :signature
      t.jsonb   :templates, null: false, default: {}                        # { "1" => { "fr" => { "subject" =>, "body" => } } }, the built-in text where absent
      t.timestamps
    end

    create_table :dunning_runs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.date    :run_on, null: false
      t.integer :status, null: false, default: 0 # prepared / sent
      t.boolean :auto, null: false, default: false
      t.timestamps
    end

    create_table :dunning_items do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :dunning_run, null: false, foreign_key: true
      t.references :partner, null: false, foreign_key: { to_table: :accounting_partners }
      t.date    :run_on, null: false
      t.integer :level, null: false
      t.integer :proposed_level, null: false
      t.boolean :skips_level, null: false, default: false
      t.boolean :skip_confirmed, null: false, default: false
      t.boolean :excluded, null: false, default: false
      t.decimal :total, precision: 15, scale: 2, null: false
      t.decimal :fees, precision: 15, scale: 2, null: false, default: 0
      t.decimal :interest, precision: 15, scale: 2, null: false, default: 0
      t.decimal :indemnity, precision: 15, scale: 2, null: false, default: 0
      t.integer :channel, null: false, default: 0   # email / letter
      t.string  :recipient
      t.string  :language, null: false, default: "fr"
      t.string  :subject
      t.text    :body
      t.integer :status, null: false, default: 0    # pending / sent / bounced / opened
      t.datetime :sent_at
      t.string  :message_id
      t.text    :error
      t.timestamps
    end
    # one campaign a day for a customer (an item left out of its run does not count)
    add_index :dunning_items, %i[partner_id run_on], unique: true, where: "NOT excluded"

    create_table :dunning_item_lines do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :dunning_item, null: false, foreign_key: true
      t.references :line, null: false, foreign_key: { to_table: :accounting_journal_entry_lines }
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.date    :due_date, null: false
      t.timestamps
    end
  end

  def down
    drop_table :dunning_item_lines
    drop_table :dunning_items
    drop_table :dunning_runs
    drop_table :dunning_policies
    execute format(LOCK_FUNCTION, columns: BEFORE)
    remove_column :accounting_partners, :language
    remove_column :accounting_partners, :email_bounced_at
    remove_column :accounting_partners, :do_not_dun
    remove_column :accounting_journal_entry_lines, :last_dunned_at
    remove_column :accounting_journal_entry_lines, :dunning_level
    remove_column :accounting_journal_entry_lines, :payment_promised_on
    remove_column :accounting_journal_entry_lines, :disputed
  end
end
