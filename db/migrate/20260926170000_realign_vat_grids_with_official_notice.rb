# Re-map already posted lines to the official grid numbers (SPF Finances notice):
# purchase base grids 81-83 follow the expense account, not the VAT rate; reverse-charge
# and sale treatments use their official grids. Purchases at 0 % that carried no grid stay without.
class RealignVatGridsWithOfficialNotice < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE accounting_journal_entry_lines l
      SET vat_code = CASE
        WHEN a.code LIKE '60%' THEN 81
        WHEN a.code LIKE '61%' OR a.code LIKE '64%' THEN 82
        WHEN a.code ~ '^2[0-7]' THEN 83
      END
      FROM accounting_accounts a
      WHERE a.id = l.account_id AND l.vat_code IN (81, 82, 83)
    SQL
    execute <<~SQL
      UPDATE accounting_journal_entry_lines
      SET vat_code = CASE vat_code
        WHEN 47 THEN 44 WHEN 48 THEN 45 WHEN 49 THEN 47
        WHEN 87 THEN 88 WHEN 88 THEN 87
        WHEN 56 THEN 55 WHEN 57 THEN 56
      END
      WHERE vat_code IN (47, 48, 49, 56, 57, 87, 88)
    SQL
  end

  def down = raise(ActiveRecord::IrreversibleMigration)
end
