require "rails_helper"

# I7 (docs/dev/reports/spec.md §2.3): the VAT return's balance equals the ledger's VAT
# movement (450100 − 410100) once lines without a grid (payments, manual entries) are set aside.
RSpec.describe "Invariant I7 — VAT return = ledger VAT accounts", type: :invariant do
  it "leaves no unexplained difference on the reference ledger" do
    entity = Seeders::ReferenceLedgerSeeder.call

    ActsAsTenant.with_tenant(entity) do
      fiscal_year = Accounting::FiscalYear.order(:start_date).last
      declaration = Accounting::GenerateVatReturn.call(
        fiscal_year_id: fiscal_year.id, period_start: fiscal_year.start_date,
        period_end: fiscal_year.end_date, period_type: "quarterly"
      )[:vat_declaration]
      skip "reference ledger yields no VAT declaration" unless declaration

      result = Accounting::VatConsistencyQuery.new(declaration: declaration).call
      expect(result.residual).to eq(0), "declared #{result.declared_balance}, gridded ledger #{result.gridded_net}"
    end
  end
end
