# F10: the guided closing of a fiscal year: a run with its 18 steps, the snapshot taken when it closes, the accounts the closing entries use, and the
# thresholds of the analytical review. A closing entry and an opening line say which run made them (`closing_run_id`) and which line they carry forward
# (`origin_line_id`), so that an open item of a partner passes into the next year one by one and is counted once.
class CreateClosingRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :closing_runs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fiscal_year, null: false, foreign_key: { to_table: :accounting_fiscal_years }
      t.integer :status, null: false, default: 0 # draft / in_progress / ready / closed / reopened
      t.references :opened_by, foreign_key: { to_table: :users }
      t.references :closed_by, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :opened_at
      t.datetime :closed_at
      t.datetime :approved_at
      t.references :reopened_by, foreign_key: { to_table: :users }
      t.datetime :reopened_at
      t.text :reopen_reason
      t.boolean :carry_forward_stale, null: false, default: false # the next year's opening entry must be recalculated after a reopening
      t.timestamps
    end

    create_table :closing_steps do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :closing_run, null: false, foreign_key: true
      t.integer :position, null: false
      t.string  :code, null: false
      t.string  :title, null: false
      t.integer :kind, null: false                 # check / action / manual / report
      t.boolean :blocking, null: false, default: true
      t.integer :status, null: false, default: 0   # pending / ok / warning / blocked / skipped / done
      t.jsonb   :result, null: false, default: {}
      t.references :completed_by, foreign_key: { to_table: :users }
      t.datetime :completed_at
      t.references :acknowledged_by, foreign_key: { to_table: :users }
      t.datetime :acknowledged_at
      t.text :comment
      t.timestamps
    end
    add_index :closing_steps, %i[closing_run_id code], unique: true

    create_table :closing_snapshots do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :closing_run, null: false, foreign_key: true, index: { unique: true }
      t.jsonb  :content, null: false
      t.string :sha256, null: false
      t.timestamps
    end

    add_reference :accounting_journal_entries, :closing_run, foreign_key: true
    add_reference :accounting_journal_entry_lines, :origin_line, foreign_key: { to_table: :accounting_journal_entry_lines }

    change_table :entities, bulk: true do |t|
      t.string  :closing_result_account_code, null: false, default: "699000" # where the closing entry gathers the result of the year
      t.string  :closing_carry_account_code,  null: false, default: "130000" # where the result stands at the opening of the next year
      t.decimal :review_threshold_pct, precision: 6, scale: 2, null: false, default: 20
      t.decimal :review_threshold_amount, precision: 15, scale: 2, null: false, default: 1000
    end
  end
end
