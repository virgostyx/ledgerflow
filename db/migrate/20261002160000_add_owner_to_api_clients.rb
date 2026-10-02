# F01: the person behind an API key. The key never has more rights than its owner, checked at every call.
# Keys issued before F01 keep a NULL owner and their former behaviour (rotating one attaches an owner).
class AddOwnerToApiClients < ActiveRecord::Migration[8.1]
  def change
    add_reference :api_clients, :owner, foreign_key: { to_table: :users }, null: true
  end
end
