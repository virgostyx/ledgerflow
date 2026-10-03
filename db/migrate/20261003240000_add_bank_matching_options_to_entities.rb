# F02: entity options of the matching engine. Exact matches are booked as drafts unless the entity asks for them to be validated;
# a difference of at most the tolerance between a payment and an invoice is booked as a rounding difference.
class AddBankMatchingOptionsToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :auto_post_exact_bank_matches, :boolean, null: false, default: false
    add_column :entities, :bank_rounding_tolerance, :decimal, precision: 15, scale: 2, null: false, default: "0.05"
  end
end
