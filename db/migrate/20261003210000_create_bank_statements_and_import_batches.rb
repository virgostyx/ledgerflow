# F02: statements (with their balances, to chain and check them) and the batches that import them. The movements stay in
# accounting_bank_transactions, extended below, so that R06, the simulator and the CAMT/CSV imports keep their one source.
class CreateBankStatementsAndImportBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_import_batches do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :document, foreign_key: { to_table: :accounting_documents }
      t.string  :parser, null: false                      # "coda"
      t.string  :source_name
      t.string  :file_sha256, null: false
      t.string  :result, null: false                      # imported / rejected
      t.integer :statements_count, null: false, default: 0
      t.integer :lines_read, null: false, default: 0
      t.integer :lines_imported, null: false, default: 0
      t.integer :lines_skipped, null: false, default: 0
      t.jsonb   :errors_list, null: false, default: []
      t.jsonb   :warnings_list, null: false, default: []
      t.timestamps
    end
    add_index :accounting_import_batches, %i[entity_id file_sha256]

    create_table :accounting_bank_statements do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :bank_account, null: false, foreign_key: { to_table: :accounting_bank_accounts }
      t.references :import_batch, null: false, foreign_key: { to_table: :accounting_import_batches }
      t.integer :sequence                                   # numéro de séquence de l'extrait codifié
      t.date    :old_balance_date
      t.decimal :old_balance, precision: 15, scale: 2, null: false
      t.date    :new_balance_date
      t.decimal :new_balance, precision: 15, scale: 2     # absent from an empty file
      t.decimal :integrity_gap, precision: 15, scale: 2, null: false, default: 0
      t.decimal :chain_gap, precision: 15, scale: 2       # opening balance minus the closing balance of the previous statement; nil = chains
      t.string  :status, null: false, default: "ok"        # ok / to_review
      t.jsonb   :messages, null: false, default: []
      t.jsonb   :header, null: false, default: {}
      t.timestamps
    end
    add_index :accounting_bank_statements, %i[bank_account_id new_balance_date]

    change_table :accounting_bank_transactions do |t|
      t.references :statement, foreign_key: { to_table: :accounting_bank_statements }
      t.string :counterparty_name
      t.string :counterparty_iban
      t.string :structured_communication
      t.string :bank_reference
      t.string :transaction_code
      t.string :fingerprint
    end
    add_index :accounting_bank_transactions, %i[bank_account_id fingerprint], unique: true, where: "fingerprint IS NOT NULL", name: "idx_bank_transactions_fingerprint"
  end
end
