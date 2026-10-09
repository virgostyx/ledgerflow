# B01a: below this amount (incl. VAT, EUR), and without a warning, invoices may be approved in bulk. Empty: bulk approval is off. Reversible.
class AddBulkThresholdToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :bulk_threshold, :decimal, precision: 15, scale: 2
  end
end
