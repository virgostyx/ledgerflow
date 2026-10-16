# B02a: the browsers a person signed in from. A sign-in from one not seen before is told to the person by e-mail (a security alert, never switched off); the person can list
# their devices and cut one off.
class CreatePortalDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_devices do |t|
      t.references :portal_user, null: false, foreign_key: true
      t.string :token, null: false # opaque, what the pages name the device by
      t.string :token_digest, null: false # of the cookie
      t.string :user_agent
      t.string :ip_address
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :portal_devices, :token_digest, unique: true
    add_index :portal_devices, :token, unique: true
    add_reference :portal_sessions, :device, foreign_key: { to_table: :portal_devices }
  end
end
