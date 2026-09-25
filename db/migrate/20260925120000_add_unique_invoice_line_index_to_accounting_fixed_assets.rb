class AddUniqueInvoiceLineIndexToAccountingFixedAssets < ActiveRecord::Migration[8.1]
  def change
    # One fixed asset per purchase invoice line.
    add_index :accounting_fixed_assets, :invoice_line_id, unique: true, where: "invoice_line_id IS NOT NULL",
              name: "index_accounting_fixed_assets_on_invoice_line_id_unique"
  end
end
