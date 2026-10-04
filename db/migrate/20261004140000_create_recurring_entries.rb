# F07: recurring entries (a template run on a schedule, as drafts or, when the owner approved it, posted) and their runs. The unique key
# (recurring entry, due date) is what keeps two instances of the job from making the same entry twice. A run outlives its recurring entry
# (nullified, with the name kept): the entries it made stay, and so does where they came from.
class CreateRecurringEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_recurring_entries do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :entry_template, null: false, foreign_key: { to_table: :accounting_entry_templates }
      t.string  :name, null: false
      t.integer :frequency, null: false, default: 0       # monthly / quarterly / yearly
      t.integer :day_of_month                             # nil: the last day of the month
      t.date    :starts_on, null: false
      t.date    :ends_on
      t.integer :max_occurrences
      t.integer :occurrences_count, null: false, default: 0
      t.date    :next_due_on, null: false
      t.integer :lead_days, null: false, default: 0
      t.integer :mode, null: false, default: 0            # draft / post
      t.decimal :base_amount, precision: 15, scale: 2
      t.decimal :indexation_percent, precision: 6, scale: 3
      t.integer :indexed_year
      t.boolean :feeds_cash_forecast, null: false, default: false
      t.integer :status, null: false, default: 0          # active / paused / finished / blocked
      t.string  :blocked_reason
      t.references :post_approved_by, foreign_key: { to_table: :users }
      t.datetime :post_approved_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :accounting_recurring_entries, %i[entity_id status next_due_on]

    create_table :accounting_recurring_runs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :recurring_entry, foreign_key: { to_table: :accounting_recurring_entries, on_delete: :nullify }
      t.string  :recurring_name, null: false
      t.date    :due_on, null: false
      t.references :journal_entry, foreign_key: { to_table: :accounting_journal_entries, on_delete: :nullify }
      t.integer :status, null: false, default: 0          # generated / blocked / failed / skipped
      t.decimal :amount, precision: 15, scale: 2
      t.string  :error
      t.timestamps
    end
    add_index :accounting_recurring_runs, %i[recurring_entry_id due_on], unique: true
  end
end
