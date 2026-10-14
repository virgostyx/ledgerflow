require "rails_helper"

# B03a critère 1 and 3, for the statements built on the trial balance: `known_at` now gives the current report, an earlier instant leaves out what came after.
RSpec.describe "Reports as known at an instant" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_entry(amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: "R-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
    entry.reload
  end

  let!(:first) { post_entry(BigDecimal("100")) }
  let!(:second) { post_entry(BigDecimal("40")) }

  def figures(report) = report.rows_by_statement.transform_values { |rows| rows.map { |r| [ r.code, r.amount ] } }
  def summary(known_at) = Accounting::JournalSummaryQuery.new(fiscal_year: fiscal_year, known_at: known_at).call.map(&:to_h)

  describe Accounting::AnnualAccounts do
    def annual(known_at = nil) = described_class.new(fiscal_year: fiscal_year, known_at: known_at).call

    it "is the current report when the instant is now or later" do
      expect(figures(annual(1.hour.from_now))).to eq(figures(annual))
      expect(figures(annual(Time.current))).to eq(figures(annual))
    end

    it "leaves out what was validated after the instant" do
      expect(figures(annual(first.posted_at))).not_to eq(figures(annual))
      expect(annual(first.posted_at).rows_by_statement[:income].sum { |r| r.level.to_i.zero? ? r.amount.abs : 0 }).to be <= annual.rows_by_statement[:income].sum { |r| r.level.to_i.zero? ? r.amount.abs : 0 }
    end

    it "keeps the instant for the monthly view too" do
      past = annual(first.posted_at).monthly_income
      now = annual.monthly_income

      expect(past.sum { |r| r.cumulative.abs }).to be < now.sum { |r| r.cumulative.abs }
    end

    it "is refused before the history" do
      expect { annual(3.days.ago) }.to raise_error(Accounting::KnownAt::Refused)
    end
  end

  describe Accounting::JournalSummaryQuery do
    it "is the current summary when the instant is now or later" do
      expect(summary(1.hour.from_now)).to eq(summary(nil))
    end

    it "counts the entries and the amounts known at the instant" do
      row = summary(first.posted_at).sole

      expect(row).to include(entry_count: 1, total_debit: 100, total_credit: 100)
      expect(summary(nil).sole).to include(entry_count: 2, total_debit: 140)
    end
  end
end
