require "rails_helper"

# R03 (docs/dev/reports/spec.md §6): "Les ruptures de numérotation dans un
# journal sont signalées". References follow Accounting::Journal#next_sequence_number
# ("PREFIXYYYY/NNNN"), sequential per journal per year.
RSpec.describe Accounting::JournalNumberingGaps, type: :service do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:account_a) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:account_b) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  def post_numbered(number)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                   entry_date: fiscal_year.start_date + number,
                   reference: "#{journal.sequence_prefix}#{fiscal_year.year}/#{number.to_s.rjust(4, '0')}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_a, debit: 10, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: account_b, debit: 0, credit: 10)
    entry.post!
  end

  it "is empty when the sequence has no gap" do
    [ 1, 2, 3 ].each { |n| post_numbered(n) }
    expect(described_class.new(journal: journal, fiscal_year: fiscal_year).call).to be_empty
  end

  it "lists the missing numbers when the sequence skips some" do
    [ 1, 2, 5, 6 ].each { |n| post_numbered(n) }
    expect(described_class.new(journal: journal, fiscal_year: fiscal_year).call).to eq([ 3, 4 ])
  end

  it "ignores a single entry (no sequence to check)" do
    post_numbered(1)
    expect(described_class.new(journal: journal, fiscal_year: fiscal_year).call).to be_empty
  end
end
