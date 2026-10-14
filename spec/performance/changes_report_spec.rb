require "rails_helper"
require "benchmark"

# B03b critère 9: the report of 10 000 changes opens, with its summary, in less than 3 seconds. The changes are written in SQL (the application would take minutes), in one
# statement, between the two instants.
RSpec.describe "Performance — the report of changes" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :misc, code: "OD") }
  let!(:customers) { create(:account, :customer, reconcilable: true) }
  let!(:revenue) { create(:account, code: "700000", label_fr: "Sales", account_type: :revenue, normal_balance: :credit, account_class: 7) }
  let(:changes) { 10_000 }

  before do
    Accounting::HistoryStart.create!(starts_at: 1.day.ago)
    conn = ApplicationRecord.connection
    ids = { journal: journal.id, year: fiscal_year.id, entity: entity.id, customers: customers.id, revenue: revenue.id }
    @t1 = instant
    next_posting_instant
    conn.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    conn.execute(<<~SQL)
      INSERT INTO accounting_journal_entries (journal_id, fiscal_year_id, entry_date, reference, status, entity_id, created_at, updated_at)
      SELECT #{ids[:journal]}, #{ids[:year]}, DATE '#{fiscal_year.start_date}' + (i % 300), 'PERF-' || i, 1, #{ids[:entity]}, now(), now() FROM generate_series(1, #{changes}) AS i
    SQL
    conn.execute(<<~SQL)
      INSERT INTO accounting_journal_entry_lines (journal_entry_id, account_id, debit, credit, entity_id, entry_date, amount_residual, created_at, updated_at)
      SELECT e.id, a.account_id, a.debit, a.credit, #{ids[:entity]}, e.entry_date, 0, now(), now()
        FROM accounting_journal_entries e
        CROSS JOIN (VALUES (#{ids[:customers]}, 100, 0), (#{ids[:revenue]}, 0, 100)) AS a(account_id, debit, credit)
       WHERE e.reference LIKE 'PERF-%'
    SQL
    conn.execute("ANALYZE accounting_journal_entries, accounting_journal_entry_lines") # the planner must know the tables are no longer empty
    @t2 = instant
  end

  it "opens the report of #{10_000} changes in less than 3 seconds, closed" do
    result = nil
    seconds = Benchmark.realtime { result = Changes::Report.call(fiscal_year: fiscal_year, from: @t1, to: @t2, show_authors: true) }

    puts format("  %d changes: %.2f s", result.total, seconds)
    expect(result.total).to eq(10_000)
    expect(result.details.size).to eq(100) # the detail is paginated
    expect(result.closing).to be_balanced
    expect(seconds).to be < 3
  end
end
