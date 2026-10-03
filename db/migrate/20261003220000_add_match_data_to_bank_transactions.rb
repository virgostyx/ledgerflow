# F02: what the matching engine found for a line (rule, score, what it points at) while it waits for a person, and how a
# match was made once booked. The status "matched" (a draft payment entry exists, not validated yet) is added in the model.
class AddMatchDataToBankTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_bank_transactions, :match_data, :jsonb, null: false, default: {}
  end
end
