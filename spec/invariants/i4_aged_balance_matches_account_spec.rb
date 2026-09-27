require "rails_helper"

# I4 (docs/dev/reports/spec.md §2.3): solde du compte 400 = total de la balance
# âgée clients ; compte 440 = balance âgée fournisseurs.
RSpec.describe "Invariant I4 — balance âgée = solde du compte collectif", type: :invariant, bullet_strict: true do
  it "holds on the reference ledger, for customers (400) and suppliers (440)" do
    entity = Seeders::ReferenceLedgerSeeder.call

    ActsAsTenant.with_tenant(entity) do
      fiscal_year = Accounting::FiscalYear.find_by!(year: 2026)
      as_of = fiscal_year.end_date

      { customer: "400000", supplier: "440000" }.each do |kind, code|
        account = Accounting::Account.find_by!(code: code)
        aged_total = Accounting::AgedBalanceQuery.totals(
          Accounting::AgedBalanceQuery.new(kind: kind, as_of: as_of).call
        ).total

        collective_balance = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: as_of)
          .call.find { |r| r.code == code }&.balance || BigDecimal("0")

        expect(aged_total).to eq(collective_balance),
          "#{kind} (#{code}): aged balance total (#{aged_total}) != account balance (#{collective_balance})"
      end
    end
  end
end
