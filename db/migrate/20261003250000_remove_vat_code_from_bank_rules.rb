# F02: a bank line has no VAT document, so a rule does not apply VAT: the draft is completed by the accountant from the invoice.
# The column was never read nor offered by any screen.
class RemoveVatCodeFromBankRules < ActiveRecord::Migration[8.1]
  def change
    remove_column :accounting_bank_rules, :vat_code, :string
  end
end
