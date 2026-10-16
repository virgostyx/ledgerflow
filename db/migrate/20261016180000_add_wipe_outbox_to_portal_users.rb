# B02b: the option "erase what is waiting to be sent when I sign out" (advised on a shared device).
class AddWipeOutboxToPortalUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :portal_users, :wipe_outbox_on_sign_out, :boolean, null: false, default: false
  end
end
