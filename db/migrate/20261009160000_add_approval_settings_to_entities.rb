# B01a: two options of the approval circuit, both off. bap_before_posting asks for the "bon à payer" before an invoice is
# validated; allow_self_approval lets the author of an invoice approve it (a one-person firm). Reversible.
class AddApprovalSettingsToEntities < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :bap_before_posting, :boolean, null: false, default: false
    add_column :entities, :allow_self_approval, :boolean, null: false, default: false
  end
end
