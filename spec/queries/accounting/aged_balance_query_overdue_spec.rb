require "rails_helper"

# docs/dev/reports/spec.md §7: colonnes "Dont échu" et "% échu" (§7 colonnes).
RSpec.describe Accounting::AgedBalanceQuery, type: :query do
  include_context "with_open_fiscal_year"

  let(:as_of)   { Date.current }
  let(:journal) { create(:journal, :purchase) }
  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:other_account)    { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }
  let(:alice) { create(:partner, name: "Alice") }

  def post_line(amount:, due_days_ago:)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: as_of)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    invoice = create(:invoice, :posted, fiscal_year: fiscal_year, due_date: as_of - due_days_ago)
    create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: alice, invoice: invoice,
           debit: BigDecimal(amount.to_s), credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: other_account, debit: 0, credit: BigDecimal(amount.to_s))
    entry.post!
  end

  it "computes the overdue amount and its share of the total" do
    post_line(amount: 60, due_days_ago: 10)  # overdue
    post_line(amount: 40, due_days_ago: -10) # not due yet

    row = described_class.new(kind: :customer, as_of: as_of).call.first
    expect(row.overdue).to eq(BigDecimal("60"))
    expect(row.overdue_pct).to eq(60.0)
  end

  it "leaves the percentage blank (nil), not infinite, when the total is zero" do
    row = Accounting::AgedBalanceQuery::Row.new(
      **Accounting::AgedBalanceQuery::Row.members.index_with { BigDecimal("0") }
    )
    expect(row.overdue_pct).to be_nil
  end
end
