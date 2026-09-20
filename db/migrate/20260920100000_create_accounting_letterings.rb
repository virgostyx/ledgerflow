class CreateAccountingLetterings < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_letterings do |t|
      t.references :entity,  null: false, foreign_key: true
      t.references :account, null: false, foreign_key: { to_table: :accounting_accounts }
      t.references :partner, foreign_key: { to_table: :accounting_partners }
      t.string :code, null: false
      t.date   :lettered_on, null: false
      t.timestamps
    end
    add_index :accounting_letterings, %i[entity_id account_id code], unique: true

    add_reference :accounting_journal_entry_lines, :lettering,
                  foreign_key: { to_table: :accounting_letterings }, index: true
  end
end
