require "rails_helper"

# I2 (docs/dev/reports/spec.md §2.3): total des soldes de la balance générale = 0.
# Vérifié par R01 — pour l'instant via Accounting::TrialBalanceQuery (l'implémentation
# existante), qui restera vraie une fois R01 reconstruit sur le socle Reports::*.
#
# Note : `row.balance` est déjà orienté "sens normal du compte" (positif quand un
# compte débiteur est débiteur, positif aussi quand un compte créditeur est
# créditeur) — utile à l'affichage, mais sa somme n'est PAS censée être nulle
# (elle vaut 2 × le solde net des comptes à sens débiteur). L'invariant porte
# sur `débit − crédit` brut, dans un sens unique, qui lui vaut 0 par construction
# double-entrée (I1) — c'est ce qu'exprime concrètement « Σ soldes débiteurs =
# Σ soldes créditeurs » de la balance de vérification.
RSpec.describe "Invariant I2 — Σ soldes de la balance générale = 0", type: :invariant, bullet_strict: true do
  it "holds on the reference ledger, for every fiscal year that has entries" do
    entity = Seeders::ReferenceLedgerSeeder.call

    ActsAsTenant.with_tenant(entity) do
      Accounting::FiscalYear.find_each do |fiscal_year|
        next unless Accounting::JournalEntry.where(fiscal_year: fiscal_year, status: :posted).exists?

        rows = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year).call
        net  = rows.sum { |r| r.total_debit - r.total_credit }
        expect(net).to eq(0), "fiscal year #{fiscal_year.year}: net debit/credit doesn't sum to zero"
      end
    end
  end
end
