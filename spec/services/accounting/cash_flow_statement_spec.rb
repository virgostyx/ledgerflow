require "rails_helper"

RSpec.describe Accounting::CashFlowStatement, type: :service, bullet_strict: true do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  def acct(code, type, normal, klass, **attrs) = create(:account, code: code, label_fr: code, account_type: type, normal_balance: normal, account_class: klass, **attrs)

  let!(:bank)      { acct("550000", :asset, :debit, 5) }
  let!(:capital)   { acct("100000", :equity, :credit, 1) }
  let!(:equipment) { acct("240000", :asset, :debit, 2) }
  let!(:accum_dep) { acct("280000", :asset, :credit, 2) }
  let!(:customers) { acct("400000", :asset, :debit, 4) }
  let!(:suppliers) { acct("440000", :liability, :credit, 4) }
  let!(:sales)     { acct("700000", :revenue, :credit, 7) }
  let!(:purchases) { acct("600000", :expense, :debit, 6) }
  let!(:rent)      { acct("610000", :expense, :debit, 6) }
  let!(:deprec)    { acct("630000", :expense, :debit, 6) }

  def post(*lines, on: fiscal_year.start_date + 10)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: on)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    lines.each { |account, debit, credit| create(:journal_entry_line, journal_entry: entry, account: account, debit: debit, credit: credit) }
    entry.post!
    entry
  end

  before do
    post([ bank, 10_000, 0 ], [ capital, 0, 10_000 ])
    post([ equipment, 3000, 0 ], [ bank, 0, 3000 ])
    post([ customers, 1000, 0 ], [ sales, 0, 1000 ])
    post([ bank, 600, 0 ], [ customers, 0, 600 ])
    post([ purchases, 400, 0 ], [ suppliers, 0, 400 ])
    post([ suppliers, 250, 0 ], [ bank, 0, 250 ])
    post([ deprec, 300, 0 ], [ accum_dep, 0, 300 ])
    post([ rent, 100, 0 ], [ bank, 0, 100 ])
  end

  let(:statement) { described_class.new(fiscal_year: fiscal_year).call }

  it "reports opening and closing cash and their difference" do
    expect([ statement.opening_cash, statement.closing_cash, statement.net_change ]).to eq([ 0, 7250, 7250 ])
  end

  it "indirect method: hand-computed sections and lines" do
    ind = statement.indirect
    expect(ind.section_total(:operating)).to eq(250)
    expect(ind.section_total(:investing)).to eq(-3000)
    expect(ind.section_total(:financing)).to eq(10_000)
    expect(ind.line(:net_result)).to eq(200)
    expect(ind.line(:non_cash)).to eq(300)
    expect(ind.line(:trade_receivables)).to eq(-400)
    expect(ind.line(:trade_payables)).to eq(150)
  end

  it "direct method: cash movements classified by their counterpart" do
    dir = statement.direct
    expect(dir.section_total(:operating)).to eq(250)
    expect(dir.section_total(:investing)).to eq(-3000)
    expect(dir.section_total(:financing)).to eq(10_000)
    expect(dir.section_total(:unclassified)).to eq(0)
  end

  it "I9: both methods equal closing − opening" do
    expect(statement.indirect.total).to eq(statement.net_change)
    expect(statement.direct.total).to eq(statement.net_change)
  end

  it "changing an account's category moves the direct classification but never the net change" do
    rent.update!(cash_flow_category: "financing")
    s = described_class.new(fiscal_year: fiscal_year).call
    expect(s.direct.section_total(:financing)).to eq(10_000 - 100)
    expect(s.direct.section_total(:operating)).to eq(250 + 100)
    expect(s.direct.total).to eq(statement.net_change)
    expect(s.indirect.total).to eq(statement.net_change)
  end

  it "keeps amounts with no category in Non classé instead of dropping them" do
    other = acct("590000", :asset, :debit, 5)
    post([ bank, 500, 0 ], [ other, 0, 500 ])
    s = described_class.new(fiscal_year: fiscal_year).call
    expect(s.direct.section_total(:unclassified)).to eq(500)
    expect(s.direct.total).to eq(s.net_change)
    expect(s.indirect.total).to eq(s.net_change)
  end

  it "excludes the closing entry and starts from the opening entry" do
    Accounting::JournalEntry.where(fiscal_year: fiscal_year).update_all(source_type: nil)
    opening = post([ bank, 1000, 0 ], [ capital, 0, 1000 ], on: fiscal_year.start_date)
    opening.update_columns(source_type: Accounting::JournalEntry::OPENING_SOURCE)
    s = described_class.new(fiscal_year: fiscal_year).call
    expect(s.opening_cash).to eq(1000)
    expect(s.net_change).to eq(7250)
    expect(s.direct.total).to eq(7250)
    expect(s.indirect.total).to eq(7250)
  end

  it "restricts to a period" do
    s = described_class.new(fiscal_year: fiscal_year, from: fiscal_year.start_date, to: fiscal_year.start_date + 5).call
    expect(s.net_change).to eq(0)
    expect(s.direct.total).to eq(0)
    expect(s.indirect.total).to eq(0)
  end
end
