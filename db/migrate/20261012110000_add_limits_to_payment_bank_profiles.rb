# B01b: the limits of a bank profile (all optional): the total of a batch, the total to one supplier in a batch, and the balance under which a batch warns.
class AddLimitsToPaymentBankProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_bank_profiles, :max_batch_total, :decimal, precision: 15, scale: 2
    add_column :payment_bank_profiles, :max_supplier_total, :decimal, precision: 15, scale: 2
    add_column :payment_bank_profiles, :balance_threshold, :decimal, precision: 15, scale: 2, null: false, default: 0
  end
end
