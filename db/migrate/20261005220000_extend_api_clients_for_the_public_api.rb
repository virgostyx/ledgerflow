# F13c: personal access tokens are API clients with an owner, scopes, an expiry and a rate of their own. Keys issued before keep the 300 requests
# a minute they always had (the default of a new token is 60). Idempotency keys keep the answer given to a POST, to give it again.
class ExtendApiClientsForThePublicApi < ActiveRecord::Migration[8.1]
  def up
    add_column :api_clients, :expires_at, :datetime
    add_column :api_clients, :rate_limit_per_minute, :integer, null: false, default: 300
    change_column_default :api_clients, :rate_limit_per_minute, from: 300, to: 60 # rows that exist keep 300

    create_table :api_idempotency_keys do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :api_client, null: false, foreign_key: true
      t.string  :key, null: false
      t.string  :request_fingerprint, null: false  # method, path and body: the same key with another request is an error
      t.integer :response_status                    # nil while the first request still runs
      t.jsonb   :response_body
      t.jsonb   :response_headers, null: false, default: {}
      t.timestamps
    end
    add_index :api_idempotency_keys, %i[api_client_id key], unique: true
    add_index :api_idempotency_keys, :created_at
  end

  def down
    drop_table :api_idempotency_keys
    remove_column :api_clients, :rate_limit_per_minute
    remove_column :api_clients, :expires_at
  end
end
