# A euro account in a bank outside SEPA (no IBAN): `iban` then holds the local account number, the BIC/SWIFT is required, and the account cannot pay a SEPA batch.
class AddNoIbanToAccountingBankAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_bank_accounts, :no_iban, :boolean, null: false, default: false
  end
end
