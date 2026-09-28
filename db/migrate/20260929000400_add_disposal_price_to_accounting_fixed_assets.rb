# R16: the disposal price (excl. VAT), used only by the movements report to show the gain or loss
# on disposal — never booked from here (the sale is invoiced on 760100).
class AddDisposalPriceToAccountingFixedAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_fixed_assets, :disposal_price, :decimal, precision: 15, scale: 2
  end
end
