class CreateAccountingPeriodLocks < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_period_locks do |t|
      t.references :entity, null: false, foreign_key: true
      t.integer :kind,   null: false, default: 0 # accounting, vat, fiscal_year
      t.integer :status, null: false, default: 0 # locked, unlocked
      t.date    :starts_on, null: false
      t.date    :ends_on,   null: false
      t.references :locked_by,   null: false, foreign_key: { to_table: :users }
      t.datetime   :locked_at,   null: false
      t.string     :lock_reason
      t.references :unlocked_by, foreign_key: { to_table: :users }
      t.datetime   :unlocked_at
      t.string     :unlock_reason
      t.timestamps
    end
    add_check_constraint :accounting_period_locks, "ends_on >= starts_on", name: "chk_period_lock_range"
    add_index :accounting_period_locks, %i[entity_id starts_on ends_on], where: "status = 0", name: "idx_period_locks_active"
  end
end
