class BackfillEntityIdOnAccountingTables < ActiveRecord::Migration[8.1]
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
    return if TABLES.all? { |t| connection.execute("SELECT COUNT(*) FROM #{t}").first["count"].to_i == 0 }

    first_user_id = connection.execute("SELECT id FROM users ORDER BY id LIMIT 1").first&.fetch("id")
    return unless first_user_id

    result = connection.execute(
      "INSERT INTO entities (name, legal_name, country, active, created_by_id, created_at, updated_at) " \
      "VALUES ('LedgerFlow Default', 'LedgerFlow Default', 'BE', true, #{first_user_id}, NOW(), NOW()) RETURNING id"
    )
    entity_id = result.first["id"]

    TABLES.each do |table|
      connection.execute("UPDATE #{table} SET entity_id = #{entity_id} WHERE entity_id IS NULL")
    end
  end

  def down
    # Non-reversible data migration — no-op on down
  end
end
