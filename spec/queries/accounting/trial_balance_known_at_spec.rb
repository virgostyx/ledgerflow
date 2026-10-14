require "rails_helper"

# B03a: R01 as it was known at an instant. Criteria 1 (now = the current report), 3 (validated at T2: absent at T1, present at T2; a reversal only from its own instant), 6 (refused
# before the start of the history).
RSpec.describe Accounting::TrialBalanceQuery, "as known at an instant" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }
  let(:user) { create(:user) }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_entry(amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: "T-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
    entry.reload
  end

  def expense_debit(known_at: nil) = described_class.new(fiscal_year: fiscal_year, known_at: known_at).call.find { |r| r.code == "604000" }&.total_debit || BigDecimal("0")

  it "gives exactly the current report when the instant is now" do
    post_entry(BigDecimal("100"))
    post_entry(BigDecimal("50"))

    current = described_class.new(fiscal_year: fiscal_year).call
    as_now = described_class.new(fiscal_year: fiscal_year, known_at: Time.current).call
    as_later = described_class.new(fiscal_year: fiscal_year, known_at: 1.hour.from_now).call

    expect(as_now.map(&:to_h)).to eq(current.map(&:to_h))
    expect(as_later.map(&:to_h)).to eq(current.map(&:to_h))
  end

  it "leaves out what was validated after the instant, and has it from its own instant" do
    first = post_entry(BigDecimal("100"))
    second = post_entry(BigDecimal("50"))

    expect(expense_debit(known_at: first.posted_at - 0.001)).to eq(0)
    expect(expense_debit(known_at: first.posted_at)).to eq(100)
    expect(expense_debit(known_at: second.posted_at - 0.001)).to eq(100)
    expect(expense_debit(known_at: second.posted_at)).to eq(150)
  end

  it "shows a reversal only from its own instant, and the original as it stood" do
    original = post_entry(BigDecimal("100"))
    reversal = Accounting::ReverseJournalEntry.call(entry: original, reason: "mistake", user: user)[:reversal].reload

    expect(original.reload).to be_reversed
    expect(expense_debit(known_at: reversal.posted_at - 0.001)).to eq(100)
    expect(described_class.new(fiscal_year: fiscal_year, known_at: reversal.posted_at).call.find { |r| r.code == "604000" }.balance).to eq(0)
  end

  it "ignores the drafts: a draft is not known until it is validated" do
    create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year)
    entry = post_entry(BigDecimal("10"))

    expect(expense_debit(known_at: entry.posted_at)).to eq(10)
  end

  it "refuses an instant before the start of the history" do
    expect { described_class.new(fiscal_year: fiscal_year, known_at: 2.days.ago).call }.to raise_error(Accounting::KnownAt::Refused, /history/i)
  end
end
