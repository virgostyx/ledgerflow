# F06 step 4: a person can pick the supplier of a message that could not choose (several partners shared an identifier): kept on the message.
class AddReviewToPeppolMessages < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounting_peppol_messages, :partner, foreign_key: { to_table: :accounting_partners, on_delete: :nullify }
  end
end
