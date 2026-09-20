class BackfillPartnerOnInvoiceTradeLines < ActiveRecord::Migration[8.1]
  # Invoice entries booked before lettering carried no partner on their receivable/payable line.
  def up
    execute <<~SQL
      UPDATE accounting_journal_entry_lines l
      SET partner_id = i.partner_id
      FROM accounting_invoices i, accounting_accounts a
      WHERE i.journal_entry_id = l.journal_entry_id
        AND a.id = l.account_id
        AND a.code IN ('400000', '440000')
        AND l.partner_id IS NULL
    SQL
  end

  def down; end
end
