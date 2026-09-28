require "rails_helper"

# I9 (docs/dev/reports/spec.md §2.3): total cash flows = change in cash of accounts 55 and 57,
# for both the indirect and the direct method.
RSpec.describe "Invariant I9 — flux de trésorerie = variation de trésorerie", type: :invariant do
  it "holds on the reference ledger for both methods" do
    entity = Seeders::ReferenceLedgerSeeder.call

    ActsAsTenant.with_tenant(entity) do
      Accounting::FiscalYear.find_each do |fiscal_year|
        s = Accounting::CashFlowStatement.new(fiscal_year: fiscal_year).call
        expect(s.indirect.total).to eq(s.net_change), "#{fiscal_year.year} indirect #{s.indirect.total} vs #{s.net_change}"
        expect(s.direct.total).to eq(s.net_change), "#{fiscal_year.year} direct #{s.direct.total} vs #{s.net_change}"
      end
    end
  end
end
