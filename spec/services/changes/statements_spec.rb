require "rails_helper"

# B03b R21 "Impact sur les états": the value at T1, at T2 and the variation, for the headings of the balance sheet and the income statement (R07, R08), the cash, the VAT grids (R09)
# and the overdue receivables (R04). Each column is the same report with `known_at` at T1, then at T2.
RSpec.describe Changes::Statements do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :misc, code: "OD") }
  let(:partner) { create(:partner, name: "Acme") }
  let!(:revenue) { create(:account, code: "700000", label_fr: "Sales", account_type: :revenue, normal_balance: :credit, account_class: 7) }
  let!(:customers) { create(:account, :customer, reconcilable: true) }
  let!(:bank) { create(:account, code: "550000", label_fr: "Bank", account_type: :asset, normal_balance: :debit, account_class: 5) }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_entry(lines, date: [ Date.current, fiscal_year.end_date ].min)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date, reference: "S-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    lines.each { |attrs| create(:journal_entry_line, journal_entry: entry, **attrs) }
    entry.post!
    next_posting_instant
  end

  def statements(from, to, **opts) = described_class.call(fiscal_year: fiscal_year, from: from, to: to, **opts)

  it "gives the headings of the income statement that moved, with the value at T1, at T2 and the variation" do
    post_entry([ { account: customers, partner: partner, debit: 100, credit: 0 }, { account: revenue, debit: 0, credit: 100 } ])
    t1 = instant
    post_entry([ { account: customers, partner: partner, debit: 40, credit: 0 }, { account: revenue, debit: 0, credit: 40 } ])
    t2 = instant

    rows = statements(t1, t2).select { |r| r.section == :income }

    expect(rows).not_to be_empty
    sales = rows.find { |r| r.code == "70" }
    expect(sales).to have_attributes(at_t1: 100, at_t2: 140, variation: 40)
    expect(rows).to all(satisfy { |r| r.variation == r.at_t2 - r.at_t1 && !r.variation.zero? })
  end

  it "gives the cash: banks and cash accounts" do
    t1 = instant
    post_entry([ { account: bank, debit: 70, credit: 0 }, { account: revenue, debit: 0, credit: 70 } ])

    cash = statements(t1, instant).find { |r| r.section == :cash }

    expect(cash).to have_attributes(at_t1: 0, at_t2: 70, variation: 70)
  end

  it "gives the receivables that are overdue, at the two instants" do
    t1 = instant
    post_entry([ { account: customers, partner: partner, debit: 200, credit: 0 }, { account: revenue, debit: 0, credit: 200 } ], date: [ fiscal_year.start_date, Date.current - 100 ].max)
    t2 = instant

    row = statements(t1, t2).find { |r| r.section == :aged && r.code == "customer" }

    expect(row).to have_attributes(at_t1: 0)
    expect(row.at_t2).to be > 0
  end

  it "gives the VAT grids that moved" do
    t1 = instant
    post_entry([ { account: customers, partner: partner, debit: 121, credit: 0 }, { account: revenue, debit: 0, credit: 100, vat_code: 54, vat_amount: 21 } ])

    grid = statements(t1, instant).find { |r| r.section == :vat && r.code == "54" }

    expect(grid).to have_attributes(at_t1: 0, at_t2: 21, variation: 21)
  end

  it "has nothing when nothing moved" do
    expect(statements(instant, instant)).to be_empty
  end
end
