require "rails_helper"

# B03b R21, the review alerts, computed from the changes. Criteria 4 (an entry in a locked period got through an unlock) and 5 (validated 40 days after its date: late, at 15).
RSpec.describe Changes::Alerts do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }
  let(:user) { create(:user) }
  let(:today) { [ Date.current, fiscal_year.end_date ].min }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_entry(date: today, amount: 10, author: user, **attrs)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date, reference: "T-#{SecureRandom.hex(3)}", created_by_id: author.id, **attrs)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
    entry.reload
  end

  def alerts(from, to, **opts)
    described_class.call(changes: Changes::Between.call(fiscal_year: fiscal_year, from: from, to: to), events: Changes::Events.call(from: from, to: to), **opts)
  end

  def kinds(list) = list.map(&:kind)

  it "flags an entry validated 40 days after its date, and not one validated within 15" do
    from = instant
    late = post_entry(date: today - 40)
    post_entry(date: today - 10)
    to = instant

    list = alerts(from, to)

    expect(list.select { |a| a.kind == :late }.map(&:subject_id)).to eq([ late.id ])
    expect(list.first.detail).to include(days: 40)
  end

  it "counts the days exactly: 15 days after the date is not late, 16 is" do
    from = instant
    fifteen = post_entry(date: today - 15)
    sixteen = post_entry(date: today - 16)
    to = instant

    expect(alerts(from, to).select { |a| a.kind == :late }.map(&:subject_id)).to eq([ sixteen.id ])
    expect(fifteen).to be_present
  end

  it "takes the threshold of the company: 15 days by default, another one when given" do
    from = instant
    post_entry(date: today - 20)
    to = instant

    expect(kinds(alerts(from, to))).to include(:late)
    expect(kinds(alerts(from, to, late_days: 30))).not_to include(:late)
  end

  it "flags an entry dated in a period that was locked, obtained through an unlock" do
    lock = Accounting::LockPeriod.call(starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date + 60, user: user, reason: "closed")[:lock]
    from = instant
    Accounting::UnlockPeriod.call(lock: lock, user: user, reason: "forgotten invoice", notify: false)
    entry = post_entry(date: fiscal_year.start_date + 20)
    to = instant

    alert = alerts(from, to).find { |a| a.kind == :locked_period }

    expect(alert.subject_id).to eq(entry.id)
    expect(alert.detail).to include(lock_id: lock.id)
  end

  it "does not flag an entry dated in a period that was locked only afterwards" do
    from = instant
    post_entry(date: fiscal_year.start_date + 20)
    Accounting::LockPeriod.call(starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date + 60, user: user, reason: "closed")
    to = instant

    expect(kinds(alerts(from, to))).not_to include(:locked_period)
  end

  it "flags an author who reverses often, from the threshold" do
    originals = Array.new(3) { post_entry }
    from = instant
    originals.each { |e| Accounting::ReverseJournalEntry.call(entry: e, reason: "mistake", user: user) }
    to = instant

    expect(kinds(alerts(from, to, reversals_per_author: 3))).to include(:frequent_reversals)
    expect(kinds(alerts(from, to, reversals_per_author: 4))).not_to include(:frequent_reversals)
  end

  it "flags a mass import: many entries of one import batch" do
    batch = Accounting::ImportBatch.create!(parser: "coda", file_sha256: "mass", result: "imported")
    from = instant
    3.times { post_entry(import_batch_id: batch.id) }
    to = instant

    alert = alerts(from, to, mass_import: 3).find { |a| a.kind == :mass_import }

    expect(alert.detail).to include(entries: 3, import_batch_id: batch.id)
    expect(kinds(alerts(from, to, mass_import: 4))).not_to include(:mass_import)
  end

  it "flags the unletterings from the threshold, and any change of IBAN" do
    from = instant
    Accounting::LetteringEvent.record!(lines: [ Struct.new(:id).new(1), Struct.new(:id).new(2) ], action: "unletter", code: "AA", user: user)
    Accounting::AuditLog.record!(auditable: fiscal_year, action: "bank_account_changed", user: user)
    to = instant

    expect(kinds(alerts(from, to, unletterings: 2))).to include(:unlettering, :iban_change)
    expect(kinds(alerts(from, to, unletterings: 3))).not_to include(:unlettering)
  end

  it "has no alert when nothing is wrong" do
    from = instant
    post_entry
    expect(alerts(from, instant)).to be_empty
  end
end
