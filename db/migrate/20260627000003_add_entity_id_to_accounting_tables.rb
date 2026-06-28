class AddEntityIdToAccountingTables < ActiveRecord::Migration[8.1]
  TABLES = %w[
    accounting_accounts
    accounting_journals
    accounting_fiscal_years
    accounting_journal_entries
    accounting_journal_entry_lines
    accounting_partners
    accounting_invoices
    accounting_invoice_lines
    accounting_vat_declarations
    accounting_bank_accounts
    accounting_bank_transactions
    accounting_analytical_axes
    accounting_analytical_accounts
    accounting_analytical_annotations
  ].freeze

  def up
    TABLES.each do |table|
      add_column table, :entity_id, :bigint
      add_index table, :entity_id, name: "index_#{table}_on_entity_id"
      add_foreign_key table, :entities, column: :entity_id
    end
  end

  def down
    TABLES.each do |table|
      remove_foreign_key table, column: :entity_id
      remove_index table, name: "index_#{table}_on_entity_id"
      remove_column table, :entity_id
    end
  end
end
