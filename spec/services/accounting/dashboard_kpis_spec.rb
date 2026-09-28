require "rails_helper"

RSpec.describe Accounting::DashboardKpis, type: :service do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  def acct(code, type, normal, klass, **attrs) = create(:account, code: code, label_fr: code, account_type: type, normal_balance: normal, account_class: klass, **attrs)

  let!(:capital)   { acct("100000", :equity, :credit, 1) }
  let!(:bank)      { acct("550000", :asset, :debit, 5) }
  let!(:customers) { acct("400000", :asset, :debit, 4) }
  let!(:suppliers) { acct("440000", :liability, :credit, 4) }
  let!(:sales)     { acct("700000", :revenue, :credit, 7) }
  let!(:purchases) { acct("600000", :expense, :debit, 6) }
  let!(:rent)      { acct("610000", :expense, :debit, 6, fixed_cost: true) }

  let(:as_of) { fiscal_year.start_date.advance(months: 3) - 1 }
  let(:days)  { (as_of - fiscal_year.start_date + 1).to_i }

  def post(lines, on: fiscal_year.start_date + 5)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: on)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    lines.each { |account, debit, credit| create(:journal_entry_line, journal_entry: entry, account: account, debit: debit, credit: credit) }
    entry.post!
  end

  before do
    post([ [ bank, 5000, 0 ], [ capital, 0, 5000 ] ])
    post([ [ customers, 1000, 0 ], [ sales, 0, 1000 ] ])
    post([ [ purchases, 600, 0 ], [ suppliers, 0, 600 ] ])
    post([ [ rent, 300, 0 ], [ bank, 0, 300 ] ])
    post([ [ bank, 400, 0 ], [ customers, 0, 400 ] ])
  end

  let(:cards) { described_class.new(fiscal_year: fiscal_year, as_of: as_of).call }
  def value(key) = cards.find { |c| c.key == key }.value

  it "matches hand-computed figures" do
    expect(value(:cash)).to eq(5100)
    expect(value(:revenue_ytd)).to eq(1000)
    expect(value(:gross_margin_pct)).to eq(40)
    expect(value(:result_ytd)).to eq(100)
    expect(value(:fixed_costs_monthly)).to eq(100)
    expect(value(:cash_coverage_months)).to eq(51)
    expect(value(:dso)).to eq(BigDecimal("600") / 1000 * days)
    expect(value(:dpo)).to eq(BigDecimal("600") / 600 * days)
    expect(value(:working_capital)).to eq(0)
  end

  it "leaves ratios empty rather than dividing by zero" do
    Accounting::JournalEntryLine.delete_all
    expect(value(:gross_margin_pct)).to be_nil
    expect(value(:dso)).to be_nil
    expect(value(:cash_coverage_months)).to be_nil
  end

  it "flags a negative cash position" do
    post([ [ suppliers, 6000, 0 ], [ bank, 0, 6000 ] ])
    expect(cards.find { |c| c.key == :cash }.status).to eq(:danger)
  end

  it "keeps the other cards when one indicator fails" do
    allow(Accounting::AgedBalanceQuery).to receive(:new).and_raise(StandardError, "boom")
    overdue = cards.find { |c| c.key == :overdue_receivables }
    expect(overdue.error).to be_present
    expect(value(:cash)).to eq(5100)
  end

  it "gives every card a formula and a source report" do
    expect(cards).to all(have_attributes(formula: be_present, source: be_present))
  end

  describe "#trends" do
    let(:trends) { described_class.new(fiscal_year: fiscal_year, as_of: as_of).trends }

    it "returns one point per elapsed month for the cheap indicators, ending on the current figure" do
      expect(trends.keys).to match_array(described_class::TREND_KEYS)
      expect(trends[:cash].size).to eq(3)
      expect(trends[:cash].last.last).to eq(5100)
      expect(trends[:cash].first.first).to eq(fiscal_year.start_date.strftime("%Y-%m"))
    end
  end

  it "can compute a subset of cards" do
    expect(described_class.new(fiscal_year: fiscal_year, as_of: as_of).call(only: [ :cash ]).map(&:key)).to eq([ :cash ])
  end
end
