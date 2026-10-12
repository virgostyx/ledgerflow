# B01b: who may authorize a payment batch. By default the person who prepared it does not (three people: who enters, who approves, who authorizes).
class AddBatchAuthorizationOptionsToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :distinct_payment_authorizer, :boolean, default: true, null: false
    add_column :entities, :authorizer_not_bap_giver, :boolean, default: false, null: false
  end
end
