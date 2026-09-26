# Sale grids 01 (6 %) and 03 (21 %) were stored the wrong way round.
class SwapSaleVatGrids01And03 < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE accounting_journal_entry_lines SET vat_code = 4 - vat_code WHERE vat_code IN (1, 3)"
  end

  def down = up
end
