require "rails_helper"

# F10, the reopening and the recalculation of the carry-forward (criterion 7): an owner, with a reason, unlocks the year and takes back its closing entry;
# the opening entry of the next year is then to be recalculated, with the differences shown first.
RSpec.describe "Closing: reopening" do
  include ActiveJob::TestHelper
  include_context "with_open_fiscal_year"

  let(:owner)      { create(:user, email: "owner@firm.test").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user, email: "acc@firm.test").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:journal) { create(:journal, :sale) }
  let!(:misc) { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let(:year_end) { fiscal_year.end_date }

  let!(:bank)      { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:capital)   { create(:account, code: "100000", label_fr: "Capital", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:customers) { create(:account, code: "400000", label_fr: "Customers", account_class: 4, account_type: :asset, normal_balance: :debit, reconcilable: true) }
  let!(:revenue)   { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:result_account) { create(:account, code: "699000", label_fr: "Result", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:carry_account)  { create(:account, code: "140100", label_fr: "Carried forward", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let(:alice) { create(:partner, name: "Alice", payment_terms_days: 30) }
  let!(:next_year) { create(:fiscal_year, status: :pre_closing, year: fiscal_year.year + 1, start_date: year_end + 1, end_date: ((year_end + 1) >> 12) - 1) }

  def post(date, *lines)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    created = lines.map { |account, side, amount, extra| create(:journal_entry_line, { journal_entry: entry, account: account, side => amount, (side == :debit ? :credit : :debit) => 0 }.merge(extra || {})) }
    entry.post!
    created
  end

  def new_run = Closing::OpenRun.call(fiscal_year: fiscal_year.reload, user: accountant)[:run]

  let!(:run) { new_run }
  let!(:alice_open) { post(fiscal_year.start_date + 20, [ customers, :debit, 600, { partner: alice } ], [ revenue, :credit, 600 ]).first }

  before do
    entity.update!(vat_regime: :franchise)
    post(fiscal_year.start_date + 1, [ bank, :debit, 10_000 ], [ capital, :credit, 10_000 ])
    run.reload
    close_year!(run: run, accountant: accountant, owner: owner)
    ActionMailer::Base.deliveries.clear
  end

  def reopen(reason: "A late invoice", user: owner) = Closing::Reopen.call(run: run.reload, user: user, reason: reason)

  it "starts from a closed year: closed, locked, the income accounts at zero and the next year open" do
    expect(fiscal_year.reload).to be_closed
    expect(next_year.reload).to be_open
    expect(Accounting::PeriodLock.in_force.where(kind: :fiscal_year)).to exist
  end

  describe "reopening" do
    it "is for an owner, with a reason" do
      expect(reopen(user: accountant)).to be_failure
      expect(reopen(reason: "")).to be_failure
      expect(fiscal_year.reload).to be_closed
    end

    it "unlocks the year and its months, takes back the closing entry, and puts the year and the next one back as they were before the closing" do
      result = reopen
      expect(result).to be_success, result.message

      expect(fiscal_year.reload).to be_open
      expect(next_year.reload).to be_pre_closing
      expect(Accounting::PeriodLock.in_force.where(kind: [ :fiscal_year, :accounting ])).to be_empty
      expect(run.reload).to have_attributes(status: "reopened", reopened_by: owner, reopen_reason: "A late invoice", carry_forward_stale: true)
      closing = Accounting::JournalEntry.find_by!(closing_run_id: run.id, source_type: Accounting::JournalEntry::CLOSING_SOURCE)
      expect(closing).to be_reversed
      balances = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: year_end).call.index_by(&:code)
      expect(balances["700000"].balance).to eq(600) # the income accounts hold their balance again
    end

    it "leaves the locks that the closing did not make: a VAT lock stays" do
      create(:period_lock, kind: :vat, starts_on: year_end - 120, ends_on: year_end - 100)
      reopen
      expect(Accounting::PeriodLock.in_force.where(kind: :vat).count).to eq(1)
    end

    it "is audited, and tells the owners once" do
      perform_enqueued_jobs { reopen }
      expect(Accounting::AuditLog.where(auditable_type: "Accounting::ClosingRun", auditable_id: run.id, action: "closing_reopened").sole.reason).to eq("A late invoice")
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.first.to).to eq([ "owner@firm.test" ])
    end

    it "is refused when the next year is already closed" do
      next_year.update_columns(status: Accounting::FiscalYear.statuses[:closed])
      result = reopen
      expect(result).to be_failure
      expect(result.message).to match(/next fiscal year.*closed/i)
      expect(fiscal_year.reload).to be_closed
    end

    it "is refused for a run that is not closed" do
      reopen
      expect(reopen).to be_failure
    end

    it "needs a controlled window when a lock that is not the closing's covers the closing entry, and changes nothing without it" do
      create(:period_lock, kind: :vat, starts_on: year_end.beginning_of_month, ends_on: year_end)
      result = reopen
      expect(result).to be_failure
      expect(result.message).to match(/controlled window/i)
      expect(fiscal_year.reload).to be_closed
      expect(Accounting::PeriodLock.in_force.where(kind: :fiscal_year)).to exist

      Accounting::OpenControlledWindow.call(user: owner, reason: "Reopening", purpose: "closing", hours: 2)
      expect(reopen).to be_success
      expect(fiscal_year.reload).to be_open
    end

    it "lets a new run be opened for the year" do
      reopen
      expect(Closing::OpenRun.call(fiscal_year: fiscal_year.reload, user: accountant)).to be_success
    end
  end

  describe "recalculating the carry-forward (criterion 7)" do
    let(:second) { reopen && new_run }

    def carry(run_to_use = second) = Closing::Registry.fetch("carry_forward").new(run_to_use)
    def close_income(run_to_use = second)
      Closing::Registry.fetch("closing_entries").new(run_to_use).perform(user: accountant)
      Closing::ValidateEntries.call(run: run_to_use, user: accountant)
    end

    it "reads as pending, to recalculate, with the opening entry of the first closing still standing" do
      second
      close_income
      result = carry.evaluate
      expect(result).to have_attributes(status: :pending)
      expect(result.details).to include("stale" => true)
    end

    it "shows the differences by account before it does anything: a late invoice moves the result, the bank and the customer" do
      second
      post(year_end - 5, [ customers, :debit, 400, { partner: alice } ], [ revenue, :credit, 400 ])
      close_income

      differences = carry.differences.index_by { |d| d["code"] }
      expect(differences["400000"]).to include("old" => "600.0", "new" => "1000.0", "difference" => "400.0")
      expect(differences["140100"]).to include("difference" => "-400.0") # a credit: the result is bigger
      expect(differences.keys).not_to include("550000") # unchanged
      expect(differences["400000"]["lines"]).to include("added" => 1, "removed" => 0)
    end

    it "reverses the first opening entry and drafts the new one, once, then is ok when the new one is validated" do
      second
      post(year_end - 5, [ customers, :debit, 400, { partner: alice } ], [ revenue, :credit, 400 ])
      close_income
      old = Accounting::JournalEntry.find_by!(closing_run_id: run.id, source_type: Accounting::JournalEntry::CARRY_FORWARD_SOURCE)

      result = carry.perform(user: accountant)
      expect(result).to be_success, result.message
      expect(old.reload).to be_reversed
      expect(result[:entry]).to be_draft
      expect { carry.perform(user: accountant) }.not_to change(Accounting::JournalEntry, :count)

      expect(Closing::ValidateEntries.call(run: second, user: accountant)).to be_success
      expect(carry.evaluate).to have_attributes(status: :ok)
      expect(run.reload.carry_forward_stale).to be(false)
    end

    it "gives the next year the new closing balances, and the same aged balance as the old year's last day" do
      second
      post(year_end - 5, [ customers, :debit, 400, { partner: alice } ], [ revenue, :credit, 400 ])
      close_income
      carry.perform(user: accountant)
      Closing::ValidateEntries.call(run: second, user: accountant)

      opening = Accounting::TrialBalanceQuery.new(fiscal_year: next_year.reload, as_of: next_year.start_date).call.index_by(&:code)
      expect(opening["400000"].closing_net).to eq(1000)
      expect(opening["140100"].closing_net).to eq(-1000)
      expect(Accounting::AgedBalanceQuery.new(kind: :customer, as_of: next_year.start_date).call.sole.total).to eq(1000)
    end

    it "is refused when a carried line was lettered in the next year: it says which, and changes nothing" do
      payment = post(next_year.start_date + 5, [ bank, :debit, 600 ], [ customers, :credit, 600, { partner: alice } ]).last
      payment.journal_entry.update_columns(fiscal_year_id: next_year.id)
      carried = Accounting::JournalEntryLine.find_by!(origin_line_id: alice_open.id)
      lettering = create(:lettering, account: customers, partner: alice)
      Accounting::JournalEntryLine.where(id: [ carried.id, payment.id ]).update_all(lettering_id: lettering.id)

      second
      close_income
      result = carry.perform(user: accountant)
      expect(result).to be_failure
      expect(result.message).to match(/lettered/i)
      expect(carried.journal_entry.reload).to be_posted
    end
  end
end
