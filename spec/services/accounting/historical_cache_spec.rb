require "rails_helper"

# B03a §"Performance et cache": what a report said at a past instant does not change, so it is kept without expiry; today's view, and an instant too recent to be sure, are not.
RSpec.describe "Cache of the historical views" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(store)
    Accounting::HistoryStart.create!(starts_at: 1.day.ago)
  end

  def post_entry(amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: "K-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
  end

  def queries_during(&block)
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    block.call
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def trial_balance(at) = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, known_at: at).call
  def expense_debit(at) = trial_balance(at).find { |r| r.code == "604000" }.total_debit

  it "answers a settled past instant from the cache, with exactly what the computation gives" do
    post_entry(BigDecimal("100"))
    at = instant
    post_entry(BigDecimal("50"))

    travel_to(2.minutes.from_now) do
      computed = trial_balance(at)
      spent = queries_during { expect(trial_balance(at).map(&:to_h)).to eq(computed.map(&:to_h)) }

      expect(spent).to be <= 3 # the history start and the places: nothing of the report itself
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::NullStore.new)
      expect(trial_balance(at).map(&:to_h)).to eq(computed.map(&:to_h))
    end
  end

  it "keeps the opening balance of a ledger with its lines" do
    customer = create(:account, :customer, reconcilable: true)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 1, reference: "K-L")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: customer, debit: 30, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: 0, credit: 30)
    entry.post!
    next_posting_instant
    at = instant

    travel_to(2.minutes.from_now) do
      ledger = -> { Accounting::GeneralLedgerQuery.new(account: customer, fiscal_year: fiscal_year, date_from: fiscal_year.start_date + 5, known_at: at) }
      first = ledger.call
      first_rows = first.call
      again = ledger.call
      again_rows = again.call

      expect(again_rows.map(&:to_h)).to eq(first_rows.map(&:to_h))
      expect(again.opening_balance).to eq(first.opening_balance).and eq(30)
    end
  end

  it "does not keep today's view, nor an instant of the last seconds" do
    post_entry(BigDecimal("100"))
    recent = instant

    trial_balance(nil)
    trial_balance(recent)

    expect(store.instance_variable_get(:@data)).to be_empty
  end

  it "keeps a result per instant" do
    post_entry(BigDecimal("100"))
    first = instant
    post_entry(BigDecimal("50"))
    second = instant

    travel_to(2.minutes.from_now) do
      expect(expense_debit(first)).to eq(100)
      expect(expense_debit(second)).to eq(150)
      expect(expense_debit(first)).to eq(100)
    end
  end
end
