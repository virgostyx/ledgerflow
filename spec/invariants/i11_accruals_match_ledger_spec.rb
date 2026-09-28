require "rails_helper"

# I11 (docs/dev/reports/spec.md §2.3): Σ regularizations by type = balance of accounts 490–493 at the cut-off.
RSpec.describe "Invariant I11 — régularisations = comptes 490 à 493", type: :invariant do
  it "holds on the reference ledger, which carries a deferred charge" do
    entity = Seeders::ReferenceLedgerSeeder.call

    ActsAsTenant.with_tenant(entity) do
      fiscal_year = Accounting::FiscalYear.find_by!(year: 2026)
      report = Accounting::AccrualsReportQuery.new(fiscal_year: fiscal_year).call

      expect(report.rows.sole.amount).to eq(BigDecimal("897.53"))
      report.checks.each { |c| expect(c.difference).to eq(0), "#{c.label}: register #{c.register} vs ledger #{c.ledger}" }
      expect(report.checks.find { |c| c.label.include?("490100") }.register).to eq(BigDecimal("897.53"))
    end
  end
end
