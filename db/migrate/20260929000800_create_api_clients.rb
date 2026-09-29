# Third-party applications allowed to push accounting data (docs/dev/api/inbound-api.md).
# The API key is only stored as a SHA-256 digest; the entity comes from the client, never from the request.
class CreateApiClients < ActiveRecord::Migration[8.1]
  def change
    create_table :api_clients do |t|
      t.bigint   :entity_id, null: false
      t.string   :name, null: false
      t.string   :key_digest, null: false
      t.string   :scopes, array: true, null: false, default: []
      t.boolean  :active, null: false, default: true
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :api_clients, :key_digest, unique: true
    add_index :api_clients, :entity_id
    add_foreign_key :api_clients, :entities

    create_table :api_requests do |t|
      t.bigint  :api_client_id, null: false
      t.string  :http_method, null: false
      t.string  :path, null: false
      t.integer :status, null: false
      t.integer :duration_ms
      t.string  :external_ref
      t.timestamps
    end
    add_index :api_requests, [ :api_client_id, :created_at ]
    add_foreign_key :api_requests, :api_clients
  end
end
