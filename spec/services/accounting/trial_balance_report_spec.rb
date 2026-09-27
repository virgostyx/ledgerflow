require "rails_helper"

RSpec.describe Accounting::TrialBalanceReport, type: :service do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:expense_account) do
    create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6)
  end
  let!(:liability_account) do
    create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4)
  end

  def post(fiscal_year:, entry_date:, amount:)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: entry_date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense_account, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: liability_account, debit: 0, credit: amount)
    entry.post!
  end

  def post_single_line(fiscal_year:, entry_date:, account:, amount:)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: entry_date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: liability_account, debit: 0, credit: amount)
    entry.post!
  end

  before { post(fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 5, amount: BigDecimal("300")) }

  subject(:report) { described_class.new(filters: filters).call }

  describe "without a comparative period" do
    let(:filters) { Reports::Filters.new(fiscal_year_id: fiscal_year.id) }

    it "returns a Reports::Result whose rows come straight from TrialBalanceQuery" do
      expect(report).to be_a(Reports::Result)
      expect(report.rows.map(&:code)).to include("604000", "440000")
      expect(report.filters).to eq(filters)
    end

    it "totals Σ debit, Σ credit and the period's result (Σ classe 7 − Σ classe 6)" do
      expect(report.totals[:debit]).to eq(BigDecimal("300"))
      expect(report.totals[:credit]).to eq(BigDecimal("300"))
      expect(report.totals[:result]).to eq(BigDecimal("-300")) # 0 (class 7) - 300 (class 6)
    end
  end

  describe "with a :previous_year comparative" do
    let(:filters) { Reports::Filters.new(fiscal_year_id: fiscal_year.id, comparative: "previous_year") }
    let!(:previous_fiscal_year) { create(:fiscal_year, entity: entity, year: fiscal_year.year - 1, status: :closed,
                                          start_date: fiscal_year.start_date.prev_year, end_date: fiscal_year.end_date.prev_year) }

    before { post(fiscal_year: previous_fiscal_year, entry_date: previous_fiscal_year.start_date + 5, amount: BigDecimal("100")) }

    it "decorates each row with the prior year's closing balance and the variation" do
      row = report.rows.find { |r| r.code == "604000" }
      expect(row.comparative_closing).to eq(BigDecimal("100"))
      expect(row.variation_amount).to eq(BigDecimal("200"))
      expect(row.variation_pct).to eq(200.0)
    end

    it "leaves the variation % blank (nil), not infinite, when the prior year had no activity at all" do
      new_account = create(:account, code: "606000", label_fr: "Nouveau compte",
                            account_type: :expense, normal_balance: :debit, account_class: 6)
      post_single_line(fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 6,
                        account: new_account, amount: BigDecimal("50"))

      row = report.rows.find { |r| r.code == "606000" }
      expect(row.comparative_closing).to eq(0)
      expect(row.variation_pct).to be_nil
    end
  end

  describe "without a matching prior fiscal year" do
    let(:filters) { Reports::Filters.new(fiscal_year_id: fiscal_year.id, comparative: "previous_year") }

    it "degrades to no comparative rather than raising" do
      row = report.rows.find { |r| r.code == "604000" }
      expect(row.comparative_closing).to eq(0)
    end
  end
end
