class MakeEntityIdNotNullOnAccountingTables < ActiveRecord::Migration[8.1]
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
      change_column_null table, :entity_id, false
    end
  end

  def down
    TABLES.each do |table|
      change_column_null table, :entity_id, true
    end
  end
end
