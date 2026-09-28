require "rails_helper"

RSpec.describe Accounting::AnalyticMarginQuery, type: :query, bullet_strict: true do
  include_context "with_open_fiscal_year"

  let!(:axis)  { create(:analytical_axis, :proj) }
  let!(:alpha) { create(:analytical_account, analytical_axis: axis, code: "PRJ-A", label_fr: "Alpha") }
  let!(:beta)  { create(:analytical_account, analytical_axis: axis, code: "PRJ-B", label_fr: "Beta") }
  let!(:gamma) { create(:analytical_account, analytical_axis: axis, code: "PRJ-C", label_fr: "Gamma") }

  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:revenue) { create(:account, code: "700000", label_fr: "Ventes", account_type: :revenue, normal_balance: :credit, account_class: 7) }
  let!(:bank)    { create(:account, code: "550000", label_fr: "Banque", account_type: :asset, normal_balance: :debit, account_class: 5) }

  def post(account, amount, split: {})
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    exp = account.account_type == "expense"
    line = create(:journal_entry_line, journal_entry: entry, account: account, debit: exp ? amount : 0, credit: exp ? 0 : amount)
    split.each { |acct, pct| create(:analytical_annotation, journal_entry_line: line, analytical_axis: axis, analytical_account: acct, percentage: pct) }
    create(:journal_entry_line, journal_entry: entry, account: bank, debit: exp ? 0 : amount, credit: exp ? amount : 0)
    entry.post!
  end

  # Alpha: 1000 revenue, 400 costs; Beta: 500 revenue, 300 costs (one 50/50 line with Alpha's); Gamma: 500 revenue, 0 costs.
  before do
    post(revenue, 1000, split: { alpha => 100 })
    post(revenue, 500,  split: { beta => 100 })
    post(revenue, 500,  split: { gamma => 100 })
    post(expense, 300,  split: { alpha => 100 })
    post(expense, 200,  split: { alpha => 50, beta => 50 })
    post(expense, 200,  split: { beta => 100 })
    post(expense, 200)   # overhead (not allocated)
  end

  def row(result, account) = result.rows.find { |r| r.analytical_account == account }

  it "computes revenue − direct costs and the margin percentage per account" do
    r = described_class.new(fiscal_year: fiscal_year, axis: axis).call
    expect([ row(r, alpha).revenue, row(r, alpha).direct_costs, row(r, alpha).margin ]).to eq([ 1000, 400, 600 ])
    expect(row(r, alpha).margin_pct).to eq(60)
    expect([ row(r, beta).direct_costs, row(r, beta).margin ]).to eq([ 300, 200 ])
  end

  it "leaves the margin percentage empty when there is no revenue" do
    post(expense, 10, split: { create(:analytical_account, analytical_axis: axis, code: "PRJ-Z") => 100 })
    r = described_class.new(fiscal_year: fiscal_year, axis: axis).call
    expect(r.rows.find { |x| x.analytical_account.code == "PRJ-Z" }.margin_pct).to be_nil
  end

  it "spreads the unallocated overhead pro rata to revenue on separate lines" do
    r = described_class.new(fiscal_year: fiscal_year, axis: axis, allocation_key: :revenue).call
    expect(r.overhead).to eq(200)
    expect(row(r, alpha).overhead_share).to eq(100)   # 1000 / 2000
    expect(row(r, beta).overhead_share).to eq(50)
    expect(row(r, gamma).overhead_share).to eq(50)
    expect(r.rows.sum(&:overhead_share)).to eq(200)
    expect(row(r, alpha).margin_after_overhead).to eq(500)
  end

  it "spreads overhead pro rata to direct costs when asked, and never loses a cent" do
    r = described_class.new(fiscal_year: fiscal_year, axis: axis, allocation_key: :direct_costs).call
    expect(r.rows.sum(&:overhead_share)).to eq(200)
    expect(row(r, gamma).overhead_share).to eq(0)
    expect(row(r, alpha).overhead_share).to be > row(r, beta).overhead_share
  end

  it "reports overhead as undistributed when the key is zero" do
    r = described_class.new(fiscal_year: fiscal_year, axis: axis, allocation_key: :direct_costs).call
    expect(r.undistributed).to eq(0)
  end
end
