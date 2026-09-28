require "rails_helper"

# I10 (docs/dev/reports/spec.md §2.3): the fixed-asset register agrees with accounts 21–24,
# their accumulated-depreciation accounts and the year's depreciation charge (630).
RSpec.describe "Invariant I10 — registre des immobilisations = comptabilité", type: :invariant, bullet_strict: true do
  it "holds on the reference ledger, which carries a depreciated asset" do
    entity = Seeders::ReferenceLedgerSeeder.call

    ActsAsTenant.with_tenant(entity) do
      fiscal_year = Accounting::FiscalYear.find_by!(year: 2026)
      result = Accounting::FixedAssetMovementsQuery.new(fiscal_year: fiscal_year).call

      expect(result.totals.cost_end).to eq(6000)
      expect(result.totals.dep_booked).to be_positive
      result.checks.each { |c| expect(c.difference).to eq(0), "#{c.label}: register #{c.register} vs ledger #{c.ledger}" }
    end
  end
end
