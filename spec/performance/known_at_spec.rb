require "rails_helper"
require "benchmark"

# B03a critère 11: the historical views stay within 20 % of the budget of the report as it is today. Both are measured the same way, on the same books, the historical one
# at an instant too recent to be cached; the best of several runs is kept, so that one slow moment of the machine does not decide.
RSpec.describe "Performance — historical views" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let(:user) { create(:user) }
  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:revenue) { create(:account, code: "700000", label_fr: "Sales", account_type: :revenue, normal_balance: :credit, account_class: 7) }
  let!(:partners) { Array.new(20) { |i| create(:partner, name: "Partner #{i}") } }
  let(:entries) { 150 }

  before do
    Accounting::HistoryStart.create!(starts_at: 1.day.ago)
    lines = []
    entries.times do |i|
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + (i % 300), reference: "P-#{i}")
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      side, other = i.even? ? %i[debit credit] : %i[credit debit]
      lines << create(:journal_entry_line, journal_entry: entry, account: customer_account, partner: partners[i % 20], side => 100, other => 0)
      create(:journal_entry_line, journal_entry: entry, account: revenue, other => 100, side => 0)
      entry.post!
    end
    lines.each_slice(2).first(30).each { |pair| Accounting::LetterLines.call(lines: pair, user: user) if pair.size == 2 && pair.map(&:partner_id).uniq.size == 1 }
    sleep 0.05
    @at = ApplicationRecord.connection.select_value("SELECT clock_timestamp()")
  end

  def best_of(runs = 5, &block) = Array.new(runs) { Benchmark.realtime(&block) }.min

  {
    "the trial balance" => ->(known) { Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year_for_spec, known_at: known).call },
    "the aged balance" => ->(known) { Accounting::AgedBalanceQuery.new(kind: :customer, known_at: known).call },
    "the open lines" => ->(known) { Accounting::UnletteredLinesQuery.new(kind: :customer, known_at: known).call },
    "the ledger" => ->(known) { Accounting::GeneralLedgerQuery.new(account: customer_account_for_spec, fiscal_year: fiscal_year_for_spec, known_at: known).call }
  }.each do |name, report|
    it "reads #{name} at an instant within 20 % of today's, plus the noise of the machine" do
      today = best_of { instance_exec(nil, &report) }
      past = best_of { instance_exec(@at, &report) }

      puts format("  %-20s today %.1f ms, past %.1f ms (%.0f %%)", name, today * 1000, past * 1000, past / today * 100)
      expect(past).to be <= today * 1.2 + 0.015
    end
  end

  def fiscal_year_for_spec = fiscal_year
  def customer_account_for_spec = customer_account
end
