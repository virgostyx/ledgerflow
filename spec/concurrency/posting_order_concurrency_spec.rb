require "rails_helper"

# B03a critère 7: under validations by several processes at once, the places and the instants of a company stay monotone: no two entries share a place,
# none is skipped, and a later place never has an earlier instant.
RSpec.describe "The order of validation under concurrency", :concurrency do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let(:journal) { create(:journal, :misc, code: "OD") }

  # the factory defers the double-entry check, which needs a transaction (the usual one is rolled back, not here)
  def entry_for(**attrs) = ApplicationRecord.transaction { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, journal: journal, reference: nil, **attrs) }

  def post_entry(entry) = -> { Current.set(user: user) { Accounting::PostJournalEntry.call(entry: Accounting::JournalEntry.find(entry.id)) } }

  it "gives consecutive places and non-decreasing instants to entries validated at the same moment" do
    entries = Array.new(4) { entry_for }

    results = concurrently(*entries.map { |e| post_entry(e) }, entity: entity)

    expect(results).to all(be_success)
    posted = Accounting::JournalEntry.where(id: entries.map(&:id)).order(:posted_seq).pluck(:posted_seq, :posted_at)
    expect(posted.map(&:first)).to eq((1..4).to_a)
    expect(posted.map(&:last)).to eq(posted.map(&:last).sort)
  end

  it "keeps a place only for what was committed: an entry whose transaction is rolled back leaves no gap" do
    entries = Array.new(3) { entry_for }
    failing = -> { ApplicationRecord.transaction { post_entry(entries.first).call; raise ActiveRecord::Rollback } }

    concurrently(failing, post_entry(entries[1]), post_entry(entries[2]), entity: entity)

    expect(Accounting::JournalEntry.where.not(posted_seq: nil).order(:posted_seq).pluck(:posted_seq)).to eq([ 1, 2 ])
  end
end
