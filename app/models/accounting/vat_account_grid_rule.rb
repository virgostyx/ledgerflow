# Purchase base grid chosen by the expense account's prefix (notice n°149-156): 60 goods,
# 61/64 various goods and services, 20-27 investments. Longest matching prefix wins.
class Accounting::VatAccountGridRule < ApplicationRecord
  self.table_name = "accounting_vat_account_grid_rules"

  enum :sens, { purchase: 1 }

  validates :account_prefix, presence: true, uniqueness: { scope: :sens }
  validates :base_grid, presence: true

  after_commit { Accounting::VatGrid.reset! }
end
