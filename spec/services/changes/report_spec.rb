require "rails_helper"

# B03b R21 as a whole: the summary, the impact, the detail in order with its keys and review state, the alerts, the filters, and the names of the authors (criterion 6).
RSpec.describe Changes::Report do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let(:other_journal) { create(:journal, :misc, code: "OD") }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }
  let(:author) { create(:user, email: "alice@example.test").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reviewer) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }

  before do
    Accounting::HistoryStart.create!(starts_at: 1.day.ago)
    [ journal, other_journal, author, reviewer ]
  end

  def post_entry(amount, journal: self.journal, author: self.author)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: [ Date.current, fiscal_year.end_date ].min, reference: "T-#{SecureRandom.hex(3)}", created_by_id: author.id)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
    entry.reload
  end

  def report(from, to = nil, **opts) = described_class.call(fiscal_year: fiscal_year, from: from, to: to, show_authors: true, **opts)

  it "gives the detail in chronological order, entries and the other changes together, each with a key" do
    from = instant
    entry = post_entry(10)
    Accounting::LockPeriod.call(starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date + 5, user: author, reason: "closed")
    result = report(from, instant)

    expect(result.details.map(&:category)).to eq(%i[entries locks])
    expect(result.details.first.key).to eq("entry:#{entry.id}")
    expect(result.details.map(&:key).uniq.size).to eq(2)
    expect(result.closing).to be_balanced
  end

  it "shows the name of the author to who may see it, and hides it from the others (criterion 6)" do
    from = instant
    post_entry(10)
    to = instant

    expect(report(from, to).details.first.author).to eq("alice@example.test")
    hidden = report(from, to, show_authors: false)

    expect(hidden.details.first.author).to eq("A user of the company")
    expect(hidden.details.first.author_id).to be_nil
    expect(hidden.alerts.map(&:detail).to_s).not_to include("alice")
  end

  it "keeps the name of an author who left the company, marked as a former user" do
    from = instant
    gone = create(:user, email: "bob@example.test").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) }
    post_entry(10, author: gone)
    to = instant
    UserEntity.find_by!(user: gone).update!(active: false)

    expect(report(from, to).details.first.author).to eq("bob@example.test (former user)")
  end

  it "gives the impact on the statements next to the impact on the accounts" do
    from = instant
    post_entry(10)

    expect(report(from, instant).statements.map(&:section)).to include(:cash).or include(:income).or include(:assets)
    expect(report(from, instant, statements: false).statements).to be_nil
  end

  it "carries the review state of each change" do
    from = instant
    entry = post_entry(10)
    Changes::Review.call(key: "entry:#{entry.id}", user: reviewer, comment: "ok")

    detail = report(from, instant).details.first

    expect(detail.reviewed_by).to eq(reviewer.email)
    expect(detail.reviewed_at).to be_present
  end

  it "keeps the entries of a journal, an author, an account, and the categories asked for" do
    from = instant
    a = post_entry(10)
    b = post_entry(20, journal: other_journal, author: reviewer)
    to = instant

    expect(report(from, to, journal_ids: [ other_journal.id ]).details.map(&:key)).to eq([ "entry:#{b.id}" ])
    expect(report(from, to, actor_ids: [ author.id ]).details.map(&:key)).to eq([ "entry:#{a.id}" ])
    expect(report(from, to, account_codes: [ "9" ]).details).to be_empty
    expect(report(from, to, account_codes: [ "604" ]).impact.map(&:code)).to eq([ "604000" ])
    expect(report(from, to, categories: %i[locks]).details).to be_empty
  end

  it "hides the neutral pairs on request, and says how many there are" do
    from = instant
    original = post_entry(10)
    Accounting::ReverseJournalEntry.call(entry: original, reason: "mistake", user: author)
    post_entry(5)
    to = instant

    all = report(from, to)
    without = report(from, to, hide_neutral: true)

    expect(all.details.size).to eq(3)
    expect(without.details.size).to eq(1)
    expect(without.summary.neutral_pairs).to eq(1)
  end

  it "adds up by month when the span is wide, and keeps the detail for the asking" do
    from = instant
    post_entry(10)
    to = instant

    expect(report(from, to).by_month).to be_nil
    wide = described_class.call(fiscal_year: fiscal_year, from: from, to: to, show_authors: true, month_threshold: 0)

    expect(wide.by_month).to eq([ { month: Date.current.beginning_of_month, entries: 1, amount: 10 } ])
  end
end
