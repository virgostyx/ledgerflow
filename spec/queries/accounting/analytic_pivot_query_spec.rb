require "rails_helper"

RSpec.describe Accounting::AnalyticPivotQuery, type: :query do
  include_context "with_open_fiscal_year"

  let!(:axis)  { create(:analytical_axis, :proj) }
  let!(:alpha) { create(:analytical_account, analytical_axis: axis, code: "PRJ-A", label_fr: "Alpha") }
  let!(:beta)  { create(:analytical_account, analytical_axis: axis, code: "PRJ-B", label_fr: "Beta") }

  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:revenue) { create(:account, code: "700000", label_fr: "Ventes", account_type: :revenue, normal_balance: :credit, account_class: 7) }
  let!(:bank)    { create(:account, code: "550000", label_fr: "Banque", account_type: :asset, normal_balance: :debit, account_class: 5) }

  # Posts `amount` on `account` against the bank; `split` = { analytical_account => pct }.
  def post(account, amount, split: {}, on: fiscal_year.start_date + 10)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: on)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    expense_side = account.account_type == "expense"
    line = create(:journal_entry_line, journal_entry: entry, account: account,
                  debit: expense_side ? amount : 0, credit: expense_side ? 0 : amount)
    split.each { |acct, pct| create(:analytical_annotation, journal_entry_line: line, analytical_axis: axis, analytical_account: acct, percentage: pct) }
    create(:journal_entry_line, journal_entry: entry, account: bank,
           debit: expense_side ? 0 : amount, credit: expense_side ? amount : 0)
    entry.post!
  end

  let(:result) { described_class.new(fiscal_year: fiscal_year, axis: axis).call }
  def cell(row_account, col) = result.rows.find { |r| r.account == row_account }.cells.fetch(col)

  before do
    post(revenue, 1000, split: { alpha => 100 })
    post(expense, 300, split: { alpha => 50, beta => 50 })   # split 50/50
    post(expense, 80)                                          # not allocated
    post(expense, 40, split: { beta => 60 })                   # partial: remainder is unassigned
  end

  it "signs revenue as credit − debit and expenses as debit − credit" do
    expect(result.rows.find { |r| r.account == revenue }.total).to eq(1000)
    expect(result.rows.find { |r| r.account == expense }.total).to eq(420)
  end

  it "weights each line by its percentage" do
    expect(cell(expense, alpha.id)).to eq(150)
    expect(cell(expense, beta.id)).to eq(150 + 24)
  end

  it "puts unallocated amounts and split remainders under Non ventilé" do
    expect(cell(expense, :unassigned)).to eq(80 + 16)
    expect(cell(revenue, :unassigned)).to eq(0)
  end

  it "keeps analytic columns + Non ventilé equal to the row total" do
    result.rows.each { |r| expect(r.cells.values.sum).to eq(r.total) }
  end

  it "exposes the net result = revenue − expenses (I8 anchor)" do
    expect(result.net_result).to eq(1000 - 420)
  end

  it "restricts to the period" do
    post(revenue, 500, on: fiscal_year.start_date + 200)
    r = described_class.new(fiscal_year: fiscal_year, axis: axis, period: fiscal_year.start_date..(fiscal_year.start_date + 30)).call
    expect(r.net_result).to eq(580)
  end

  it "pivots by month" do
    post(revenue, 500, on: fiscal_year.start_date + 40)
    r = described_class.new(fiscal_year: fiscal_year, axis: axis, columns: :month).call
    months = r.columns
    expect(months).to eq(months.sort)
    row = r.rows.find { |x| x.account == revenue }
    expect(row.cells.values.sum).to eq(1500)
    expect(row.cells.size).to eq(2)
  end

  it "ignores draft entries" do
    draft = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 5)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: draft, account: expense, debit: 999, credit: 0)
    expect(result.net_result).to eq(580)
  end
end
