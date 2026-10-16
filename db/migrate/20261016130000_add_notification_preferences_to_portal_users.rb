# B02a: how often a person from outside is told by e-mail that something was published (security alerts are not a preference).
class AddNotificationPreferencesToPortalUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :portal_users, :notification_frequency, :string, null: false, default: "immediate" # immediate daily off
    add_column :portal_users, :last_digest_at, :datetime
  end
end
