# F01: backup codes of the second factor (TOTP) are a set of their own, apart from the recovery codes of passkeys:
# regenerating one never touches the other, and one never opens the other's door. Existing codes are passkey codes.
class AddKindToRecoveryCodes < ActiveRecord::Migration[8.1]
  def change
    add_column :recovery_codes, :kind, :string, null: false, default: "passkey"
    add_index :recovery_codes, %i[user_id kind]
  end
end
