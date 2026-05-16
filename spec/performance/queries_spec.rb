require "rails_helper"
require "benchmark"

# Performance and N+1 regression tests for accounting queries.
# These verify query count stays constant as data grows (no N+1),
# and that response times stay under acceptable thresholds.
RSpec.describe "Performance — accounting queries", type: :model do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:purchase_journal) { create(:journal, :purchase) }
  let!(:expense_account) do
    create(:account, code: "604100", label_fr: "Services perf",
           account_type: :expense, normal_balance: :debit, account_class: 6)
  end
  let!(:liability_account) do
    create(:account, code: "440100", label_fr: "Fournisseurs perf",
           account_type: :liability, normal_balance: :credit, account_class: 4)
  end

  before(:context) { GC.compact if GC.respond_to?(:compact) }

  def create_posted_entries(n)
    n.times do |i|
      entry = create(:journal_entry, :draft, journal: purchase_journal,
                     fiscal_year: fiscal_year,
                     entry_date: fiscal_year.start_date + i)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: expense_account,
             debit: BigDecimal("100.00"), credit: BigDecimal("0"))
      create(:journal_entry_line, journal_entry: entry, account: liability_account,
             debit: BigDecimal("0"), credit: BigDecimal("100.00"))
      entry.post!
    end
  end

  def count_select_queries(&block)
    count = 0
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 if payload[:sql].start_with?("SELECT")
    end
    block.call
    ActiveSupport::Notifications.unsubscribe(subscription)
    count
  end

  describe "Accounting::TrialBalanceQuery" do
    before { create_posted_entries(30) }

    it "effectue un nombre fixe de requêtes SQL (pas de N+1)" do
      selects = count_select_queries do
        Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year).call
      end
      expect(selects).to be <= 3
    end

    it "se termine en moins de 500ms avec 30 écritures" do
      elapsed = Benchmark.measure do
        Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year).call
      end
      expect(elapsed.real).to be < 0.5
    end
  end

  describe "Accounting::GeneralLedgerQuery" do
    before { create_posted_entries(30) }

    it "effectue un nombre fixe de requêtes SQL (pas de N+1)" do
      selects = count_select_queries do
        Accounting::GeneralLedgerQuery.new(
          account:    expense_account,
          fiscal_year: fiscal_year,
          date_from:  fiscal_year.start_date,
          date_to:    fiscal_year.end_date
        ).call
      end
      expect(selects).to be <= 2
    end

    it "se termine en moins de 500ms avec 30 écritures" do
      elapsed = Benchmark.measure do
        Accounting::GeneralLedgerQuery.new(
          account:    expense_account,
          fiscal_year: fiscal_year,
          date_from:  fiscal_year.start_date,
          date_to:    fiscal_year.end_date
        ).call
      end
      expect(elapsed.real).to be < 0.5
    end
  end

  describe "Accounting::AnalyticProjectQuery" do
    before do
      30.times do |i|
        entry = create(:journal_entry, :draft, journal: purchase_journal,
                       fiscal_year: fiscal_year,
                       entry_date: fiscal_year.start_date + i,
                       project_id: (i % 5) + 1)
        ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
        create(:journal_entry_line, journal_entry: entry, account: expense_account,
               debit: BigDecimal("200.00"), credit: BigDecimal("0"))
        create(:journal_entry_line, journal_entry: entry, account: liability_account,
               debit: BigDecimal("0"), credit: BigDecimal("200.00"))
        entry.post!
      end
    end

    it "effectue une seule requête SQL (GROUP BY, pas de N+1)" do
      selects = count_select_queries do
        Accounting::AnalyticProjectQuery.new(fiscal_year: fiscal_year).call
      end
      expect(selects).to be <= 2
    end

    it "se termine en moins de 500ms avec 30 écritures" do
      elapsed = Benchmark.measure do
        Accounting::AnalyticProjectQuery.new(fiscal_year: fiscal_year).call
      end
      expect(elapsed.real).to be < 0.5
    end
  end
end
