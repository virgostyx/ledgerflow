require "rails_helper"

# I8 (docs/dev/reports/spec.md §2.3): analytic total (allocated + Non ventilé) = income statement result.
RSpec.describe "Invariant I8 — total analytique = compte de résultat", type: :invariant do
  it "holds on the reference ledger, with allocated and unallocated lines" do
    entity = Seeders::ReferenceLedgerSeeder.call

    ActsAsTenant.with_tenant(entity) do
      fiscal_year = Accounting::FiscalYear.find_by!(year: 2026)
      axis   = Accounting::AnalyticalAxis.find_by!(code: "PROJ")
      pivot  = Accounting::AnalyticPivotQuery.new(fiscal_year: fiscal_year, axis: axis).call
      report = Accounting::AnnualAccounts.new(fiscal_year: fiscal_year).call
      result = report.rows(:income).find { |r| r.code == "9904" }.amount

      expect(pivot.rows.flat_map { |r| r.cells.keys }.uniq).to include(:unassigned, *Accounting::AnalyticalAccount.pluck(:id))
      expect(pivot.net_result).to eq(result)
    end
  end
end
