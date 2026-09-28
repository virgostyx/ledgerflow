require "rails_helper"

RSpec.describe Accounting::StaleCreditsQuery, type: :query do
  include_context "with_open_fiscal_year"

  let(:as_of)   { Date.current }
  let(:journal) { create(:journal, :purchase) }

  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:other_account)    { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }

  let(:alice) { create(:partner, name: "Alice") }
  let(:bob)   { create(:partner, name: "Bob") }

  # Posts a two-line entry: `amount` on customer_account (debit or credit) against 700000.
  def post_line(side:, amount:, partner:, days_ago: 0)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: as_of - days_ago)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    other = side == :debit ? :credit : :debit
    line = create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: partner,
                  side => BigDecimal(amount.to_s), other => BigDecimal("0"))
    create(:journal_entry_line, journal_entry: entry, account: other_account,
           other => BigDecimal(amount.to_s), side => BigDecimal("0"))
    entry.post!
    line
  end

  def rows(min_age_days: 90) = described_class.new(kind: :customer, as_of: as_of, min_age_days: min_age_days).call

  it "lists an unallocated credit older than the threshold" do
    post_line(side: :credit, amount: 30, partner: alice, days_ago: 91)

    row = rows.first
    expect(row.partner_name).to eq("Alice")
    expect(row.amount).to eq(BigDecimal("30"))
    expect(row.age_days).to eq(91)
  end

  it "excludes a credit not yet older than the threshold" do
    post_line(side: :credit, amount: 30, partner: alice, days_ago: 89)
    expect(rows).to be_empty
  end

  it "excludes an open debit (a normal unpaid invoice, not a credit)" do
    post_line(side: :debit, amount: 30, partner: alice, days_ago: 91)
    expect(rows).to be_empty
  end

  it "excludes a fully allocated credit" do
    credit = post_line(side: :credit, amount: 30, partner: alice, days_ago: 91)
    debit  = post_line(side: :debit, amount: 30, partner: alice, days_ago: 91)
    Accounting::LineAllocation.create!(debit_line: debit, credit_line: credit, amount: 30, allocated_on: Date.current)

    expect(rows).to be_empty
  end

  it "respects a custom threshold" do
    post_line(side: :credit, amount: 30, partner: alice, days_ago: 61)
    expect(rows(min_age_days: 90)).to be_empty
    expect(rows(min_age_days: 60).first.amount).to eq(BigDecimal("30"))
  end

  it "sorts oldest first" do
    post_line(side: :credit, amount: 10, partner: alice, days_ago: 95)
    post_line(side: :credit, amount: 20, partner: bob,   days_ago: 200)

    expect(rows.map(&:partner_name)).to eq([ "Bob", "Alice" ])
  end
end
