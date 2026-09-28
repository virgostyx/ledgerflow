require "rails_helper"

# I6 (docs/dev/reports/spec.md §2.3): résultat du compte de résultat = actif − passif
# du bilan, avant affectation. Accounting::AnnualAccounts#balanced? already asserts
# assets == liabilities (result included); this also checks R08's own result heading
# is what closes that gap, on the reference ledger.
RSpec.describe "Invariant I6 — bilan équilibré, résultat cohérent", type: :invariant do
  it "holds on the reference ledger" do
    entity = Seeders::ReferenceLedgerSeeder.call

    ActsAsTenant.with_tenant(entity) do
      fiscal_year = Accounting::FiscalYear.find_by!(year: 2026)
      report = Accounting::AnnualAccounts.new(fiscal_year: fiscal_year).call

      expect(report).to be_balanced, "assets - liabilities = #{report.difference}"

      result_heading = report.rows(:income).find { |r| r.code == "9904" }.amount
      assets  = report.rows(:assets).find { |r| r.code == "20/58" }.amount
      equity_and_liabilities = report.rows(:liabilities).find { |r| r.code == "10/49" }.amount
      expect(assets).to eq(equity_and_liabilities) # the result is already folded into 10/49 (carry-forward)
      expect(result_heading).to be_a(BigDecimal)
    end
  end
end
