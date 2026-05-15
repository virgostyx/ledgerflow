class CreateAccountingJournals < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_journals do |t|
      t.string  :code,             null: false, limit: 5
      t.string  :label_fr,         null: false
      t.integer :journal_type,     null: false  # purchase/sale/bank/cash/misc/payroll
      t.bigint  :default_account_id
      t.string  :sequence_prefix,  null: false
      t.integer :current_sequence, null: false, default: 0
      t.boolean :active,           null: false, default: true
      t.timestamps
    end

    add_index :accounting_journals, :code, unique: true
  end
end
