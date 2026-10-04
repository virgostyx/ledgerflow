require "rails_helper"

# F07 §10: "Duplicate" on any entry: a draft with the same lines, no reversal link, nothing carried over from the original's life.
RSpec.describe Accounting::DuplicateJournalEntry do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user)    { create(:user, role: :accountant) }
  let(:journal) { create(:journal, :cash) }

  def posted_entry(**attrs)
    entry = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, status: :draft, description: "Rent", **attrs)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: 500, credit: 0, label: "Rent")
    create(:journal_entry_line, journal_entry: entry, account: account_440, debit: 0, credit: 500, label: "Landlord", partner: create(:partner, :supplier))
    Accounting::PostJournalEntry.call!(entry: entry)
    entry.reload
  end

  it "makes a draft with the same journal, description and lines" do
    original = posted_entry
    result = described_class.call(entry: original, user: user)

    copy = result[:entry]
    expect(result).to be_success
    expect(copy).to be_draft
    expect(copy).to have_attributes(journal_id: journal.id, description: "Rent", created_by_id: user.id)
    expect(copy.lines.map { |l| [ l.account_id, l.partner_id, l.debit, l.credit, l.label ] }).to match_array(original.lines.map { |l| [ l.account_id, l.partner_id, l.debit, l.credit, l.label ] })
  end

  it "carries no link to the original: no reversal, no source, no reference, no planned reversal" do
    original = posted_entry(auto_reverse_on: fiscal_year.start_date + 90)
    original.update_columns(source_type: "Accounting::Invoice", source_id: 1)

    copy = described_class.call(entry: original, user: user)[:entry]

    expect(copy).to have_attributes(reversal_of_id: nil, source_type: nil, source_id: nil, reference: nil, auto_reverse_on: nil, vat_regularisation: false)
  end

  it "can copy a draft, a posted and a reversed entry" do
    original = posted_entry
    Accounting::ReverseJournalEntry.call(entry: original, reason: "x", user: user)

    expect(described_class.call(entry: original.reload, user: user)).to be_success
    expect(described_class.call(entry: original.reversal, user: user)).to be_success
  end

  it "is dated today when an open fiscal year covers today, else like the original" do
    original = posted_entry
    copy = described_class.call(entry: original, user: user)[:entry]

    expect(copy.entry_date).to eq(Date.current)
    fiscal_year.update_columns(start_date: Date.new(2020, 1, 1), end_date: Date.new(2020, 12, 31))
    original.update_columns(entry_date: Date.new(2020, 3, 1))

    expect(described_class.call(entry: original, user: user)[:entry].entry_date).to eq(Date.new(2020, 3, 1))
  end
end
