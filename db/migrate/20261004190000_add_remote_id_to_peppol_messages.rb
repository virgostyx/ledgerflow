# F06 step 6: a document announced by the Access Point (a webhook that carries no XML) is recorded first, with the Access Point's own identifier,
# and its XML is fetched afterwards.
class AddRemoteIdToPeppolMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_peppol_messages, :remote_id, :string
  end
end
