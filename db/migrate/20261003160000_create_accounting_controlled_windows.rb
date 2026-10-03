# F01: the controlled window (spec §4): a time-limited, reasoned, audited exception that lets migration (F05) and closing
# (F10) write into locked periods. See Accounting::ControlledWindow.
class CreateAccountingControlledWindows < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_controlled_windows do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :opened_by, null: false, foreign_key: { to_table: :users }
      t.references :closed_by, foreign_key: { to_table: :users }
      t.string   :purpose, null: false
      t.string   :reason,  null: false
      t.datetime :opens_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :closed_at
      t.timestamps
    end
    add_index :accounting_controlled_windows, %i[entity_id expires_at]
  end
end
