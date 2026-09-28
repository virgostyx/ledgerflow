require "rails_helper"

# I5 (docs/dev/reports/spec.md §2.3): solde comptable du compte 55x = solde du relevé
# ± opérations en suspens. Le jeu de référence couvre déjà rapproché/BN/SN/paiement
# groupé/virement interne (§15) — vérifié ici via Accounting::BankReconciliationQuery.
RSpec.describe "Invariant I5 — solde bancaire = relevé ± suspens", type: :invariant do
  it "holds a zero gap on every reference bank account" do
    entity = Seeders::ReferenceLedgerSeeder.call

    ActsAsTenant.with_tenant(entity) do
      Accounting::BankAccount.find_each do |bank_account|
        result = Accounting::BankReconciliationQuery.new(bank_account: bank_account, as_of: Date.current).call
        expect(result.gap).to eq(0), "#{bank_account.label_fr}: gap = #{result.gap} (BN: #{result.bn.size}, SN: #{result.sn.size})"
      end
    end
  end
end
