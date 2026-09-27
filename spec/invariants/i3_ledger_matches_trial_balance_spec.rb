require "rails_helper"

# I3 (docs/dev/reports/spec.md §2.3): total du grand livre d'un compte =
# ligne du même compte dans la balance. Vérifié par R01, R02 — pour l'instant
# via Accounting::TrialBalanceQuery/GeneralLedgerQuery (l'implémentation
# existante), qui restera vraie une fois R01/R02 reconstruits sur le socle
# Reports::*. Both queries sign the balance the same way (the account's own
# normal_balance direction), so comparing them for the same account is valid.
RSpec.describe "Invariant I3 — grand livre = balance, par compte", type: :invariant, bullet_strict: true do
  it "holds on the reference ledger, for every account with activity in 2026" do
    entity = Seeders::ReferenceLedgerSeeder.call

    ActsAsTenant.with_tenant(entity) do
      fiscal_year  = Accounting::FiscalYear.find_by!(year: 2026)
      trial_rows   = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year).call.index_by(&:id)

      trial_rows.each_value do |row|
        account = Accounting::Account.find(row.id)
        ledger  = Accounting::GeneralLedgerQuery.new(account: account, fiscal_year: fiscal_year).call
        next if ledger.empty? # closing entries etc. may post to accounts with no direct lines this year

        expect(ledger.last.running_balance).to eq(row.balance),
          "account #{account.code}: general ledger closing balance (#{ledger.last.running_balance}) " \
          "!= trial balance (#{row.balance})"
      end
    end
  end
end
