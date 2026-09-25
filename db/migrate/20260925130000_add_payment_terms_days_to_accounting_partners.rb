class AddPaymentTermsDaysToAccountingPartners < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_partners, :payment_terms_days, :integer, null: false, default: 30
  end
end
