# F10 (decided 2026-10-05): the result of a closed year is carried forward to 140100 "Bénéfice reporté" (a profit) or 140200 "Perte reportée" (a loss), the leaf
# accounts of the PCMN, instead of 130000, which is the heading "Réserves". This changes the DEFAULTS of new entities and adds the account of the losses; the entities that
# exist keep their settings until `bin/rails closing:use_retained_earnings_accounts` moves them (it only moves those whose chart has both accounts). Reversible.
class CarryForwardToRetainedEarningsAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :entities, :closing_loss_account_code, :string, null: false, default: "140200"
    change_column_default :entities, :closing_carry_account_code, from: "130000", to: "140100"
  end
end
