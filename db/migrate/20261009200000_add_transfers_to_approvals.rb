# B01a: an approver hands a request to another approver. The decision keeps who it was handed to; the request keeps, for the current level,
# who may now decide for whom ({ transferee_id => the person who handed over }). Reversible.
class AddTransfersToApprovals < ActiveRecord::Migration[8.1]
  def change
    add_reference :approval_decisions, :transferred_to, foreign_key: { to_table: :users }
    add_column :approval_requests, :transfers, :jsonb, null: false, default: {}
  end
end
