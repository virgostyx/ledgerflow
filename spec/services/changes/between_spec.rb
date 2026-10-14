require "rails_helper"

# B03b R21, core: what changed between two instants - the entries added, the reversals, the neutral pairs, the impact per account, and the closing (I14).
# Criteria 1 (closing exact), 2 (an entry between T1 and T2 is in the detail and the impact, one before or after is not), 3 (a validation and its reversal: a neutral pair).
RSpec.describe Changes::Between do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }
  let(:user) { create(:user) }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_entry(amount, date: fiscal_year.start_date + 10)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date, reference: "T-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
    entry.reload
  end

  def report(from, to, **opts) = described_class.call(fiscal_year: fiscal_year, from: from, to: to, **opts)

  it "lists the entry validated between the two instants, and not the ones before or after" do
    before = post_entry(10)
    t1 = instant
    inside = post_entry(40)
    t2 = instant
    post_entry(5)

    result = report(t1, t2)

    expect(result.added.map(&:id)).to eq([ inside.id ])
    expect(result.added.first).to have_attributes(reference: inside.reference, entry_date: inside.entry_date, amount: 40)
    expect(result.added.map(&:id)).not_to include(before.id)
  end

  it "gives the impact of each account: the value at T1, at T2 and the variation" do
    post_entry(10)
    t1 = instant
    post_entry(40)
    t2 = instant

    row = report(t1, t2).impact.find { |r| r.code == "604000" }

    expect(row).to have_attributes(at_t1: 10, at_t2: 50, variation: 40, movements: 40)
  end

  it "closes: for each account the variation equals the movements of the lines validated between the instants (I14)" do
    post_entry(10)
    t1 = instant
    post_entry(40)
    original = post_entry(7)
    Accounting::ReverseJournalEntry.call(entry: original, reason: "mistake", user: user)
    t2 = instant

    result = report(t1, t2)

    expect(result.closing).to be_balanced
    expect(result.closing.gap).to eq(0)
    expect(result.impact).to all(satisfy { |r| r.variation == r.movements })
  end

  it "marks a validation and its reversal inside the interval as a neutral pair that leaves the balances alone" do
    t1 = instant
    original = post_entry(30)
    reversal = Accounting::ReverseJournalEntry.call(entry: original, reason: "mistake", user: user)[:reversal].reload
    t2 = instant

    result = report(t1, t2)

    expect(result.reversals.map(&:id)).to eq([ reversal.id ])
    expect(result.reversals.first).to have_attributes(reversal_of_id: original.id, reason: "mistake")
    expect(result.neutral_pairs).to eq([ [ original.id, reversal.id ] ])
    expect(result.impact.find { |r| r.code == "604000" }).to have_attributes(variation: 0, movements: 0)
  end

  it "shows a reversal of an older entry as a change, not as a neutral pair" do
    original = post_entry(30)
    t1 = instant
    reversal = Accounting::ReverseJournalEntry.call(entry: original, reason: "mistake", user: user)[:reversal].reload
    t2 = instant

    result = report(t1, t2)

    expect(result.neutral_pairs).to be_empty
    expect(result.reversals.map(&:id)).to eq([ reversal.id ])
    expect(result.impact.find { |r| r.code == "604000" }.variation).to eq(-30)
  end

  it "counts the same perimeter at both instants: an entry dated after the cut-off is out of both" do
    t1 = instant
    post_entry(40, date: fiscal_year.end_date)
    t2 = instant

    result = report(t1, t2, as_of: fiscal_year.start_date + 30)

    expect(result.added).to be_empty
    expect(result.impact).to be_empty
  end

  it "never shows a draft" do
    t1 = instant
    create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year)

    expect(report(t1, instant).added).to be_empty
  end

  it "summarises: entries, reversals, movements, accounts touched" do
    t1 = instant
    post_entry(10)
    post_entry(20)
    t2 = instant

    expect(report(t1, t2).summary).to have_attributes(entries: 2, reversals: 0, movements: 30, accounts: 2)
  end

  it "orders entries validated at the same instant by their place" do
    t1 = instant
    a = post_entry(10)
    ApplicationRecord.transaction { next_posting_instant }
    b = post_entry(20)
    t2 = instant

    expect(report(t1, t2).added.map(&:id)).to eq([ a.id, b.id ])
  end

  it "refuses T1 before the start of the history, with the explanation" do
    expect { report(3.days.ago, Time.current) }.to raise_error(Accounting::KnownAt::Refused, /history/i)
  end

  it "refuses T1 after T2, and proposes to swap them" do
    expect { report(Time.current, 1.hour.ago) }.to raise_error(Changes::Between::Invalid, /swap|invert|before/i)
  end

  it "takes today as T2 when none is given" do
    t1 = instant
    post_entry(10)

    expect(report(t1, nil).added.size).to eq(1)
  end
end
