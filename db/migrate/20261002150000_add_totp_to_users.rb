# F01: second factor (TOTP). The secret is stored encrypted; totp_last_step is the last time step accepted, so a
# code cannot be used twice.
class AddTotpToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :totp_secret, :string
    add_column :users, :totp_enabled_at, :datetime
    add_column :users, :totp_last_step, :bigint
  end
end
