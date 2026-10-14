require "rails_helper"

# B03b criterion 10: a gap in the closing (I14) that is caused on purpose creates the anomaly C21 in R19, and the report is not exported officially.
RSpec.describe "The closing of the report of changes (I14)" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_entry(amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: [ Date.current, fiscal_year.end_date ].min, reference: "T-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
  end

  # What a corrupted history would do: the balance known today is not the balance known before plus what was posted since.
  def corrupt_the_balance
    original = Accounting::TrialBalanceQuery.instance_method(:call)
    allow_any_instance_of(Accounting::TrialBalanceQuery).to receive(:call) do |query|
      original.bind_call(query).each { |row| row.total_debit += 1 if row.code == "604000" && query.instance_variable_get(:@known_at).current? }
    end
  end

  it "stays closed, and creates nothing, when the history holds" do
    from = instant
    post_entry(10)

    expect(Changes::Between.call(fiscal_year: fiscal_year, from: from).closing).to be_balanced
    expect(Accounting::Consistency::Checks::C21ChangesClosing.new(fiscal_year: fiscal_year).call).to be_empty
  end

  it "shows the gap, account by account, in the closing" do
    from = instant
    post_entry(10)
    corrupt_the_balance

    closing = Changes::Between.call(fiscal_year: fiscal_year, from: from).closing

    expect(closing).not_to be_balanced
    expect(closing.gap).to eq(1)
  end

  it "is the blocking anomaly C21 of R19, found by the check and recorded by the guard" do
    post_entry(10)
    corrupt_the_balance
    result = Changes::Report.call(fiscal_year: fiscal_year, from: Time.current - 1.hour)

    expect(Accounting::Consistency::Checks::C21ChangesClosing.severity).to eq("blocking")
    expect(Changes::ClosingGuard.call(result, fiscal_year: fiscal_year)).to be(false)
    finding = Accounting::ConsistencyFinding.where(check_id: "C21").sole
    expect(finding.message).to include("604000")
    expect(Accounting::ConsistencyRun.last.trigger).to eq("changes_report")
  end

  it "lets an exact report go, without a run" do
    post_entry(10)
    result = Changes::Report.call(fiscal_year: fiscal_year, from: Time.current - 1.hour)

    expect { expect(Changes::ClosingGuard.call(result, fiscal_year: fiscal_year)).to be(true) }.not_to change(Accounting::ConsistencyRun, :count)
  end

  it "is not a check that only runs by itself: the runner can be asked for it alone" do
    post_entry(10)
    corrupt_the_balance

    run = Accounting::Consistency::Runner.call(trigger: "changes_report", fiscal_year: fiscal_year, checks: [ Accounting::Consistency::Checks::C21ChangesClosing ])

    expect(Accounting::ConsistencyFinding.where(run_id: run.id).pluck(:check_id).uniq).to eq([ "C21" ])
  end
end
