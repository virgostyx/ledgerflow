# F06 step 5: a sent message that met a technical error is tried again (attempts, next try); the acknowledgement of the Access Point is kept.
class AddRetryAndAckToPeppolMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_peppol_messages, :attempts, :integer, null: false, default: 0
    add_column :accounting_peppol_messages, :next_attempt_at, :datetime
    add_column :accounting_peppol_messages, :ack, :text
  end
end
