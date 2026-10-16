# B02a: a client cannot invite anyone, not even themselves: a director asks, the firm decides.
class CreatePortalAccessRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_access_requests do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :requested_by, null: false, foreign_key: { to_table: :portal_users }
      t.string :token, null: false
      t.string :email, null: false
      t.string :full_name, null: false
      t.string :role, null: false
      t.text :note
      t.string :status, null: false, default: "pending" # pending granted declined
      t.references :decided_by, foreign_key: { to_table: :users }
      t.datetime :decided_at
      t.timestamps
    end
    add_index :portal_access_requests, :token, unique: true
  end
end
