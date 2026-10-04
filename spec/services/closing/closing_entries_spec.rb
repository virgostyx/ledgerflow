require "rails_helper"

# F10, step 15: the closing entry. Drafted by the step, validated by a person in a batch (criterion 5), inside the controlled window when a lock covers its
# date. The result account is the entity's setting.
RSpec.describe "Closing: closing entries" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:owner)      { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:assistant)  { create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:run) { Closing::OpenRun.call(fiscal_year: fiscal_year, user: accountant)[:run] }
  let(:journal) { create(:journal, :purchase) }
  let!(:misc) { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let!(:result_account) { create(:account, code: "699000", label_fr: "Result of the year", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let(:year_end) { fiscal_year.end_date }

  def step = Closing::Registry.fetch("closing_entries").new(run)
  def outcome = step.evaluate

  def book(debit, credit, amount, date: fiscal_year.start_date + 10)
    e = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: e, account: debit, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: e, account: credit, debit: 0, credit: amount)
    e.post!
  end

  before do
    account_440.update!(account_type: :liability, normal_balance: :credit)
    account_700.update!(account_type: :revenue, normal_balance: :credit)
    book(account_604, account_440, 400)   # expense
    book(account_440, account_700, 1000)  # revenue
  end

  describe "drafting" do
    it "makes one balanced DRAFT entry dated at the last day, tagged with the run, that settles the income accounts into the result account" do
      result = step.perform(user: accountant)
      expect(result).to be_success, result.message

      entry = result[:entry]
      expect(entry).to be_draft
      expect(entry).to have_attributes(entry_date: year_end, closing_run_id: run.id, source_type: Accounting::JournalEntry::CLOSING_SOURCE)
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
      expect(entry.lines.find_by(account: account_700).debit).to eq(1000)
      expect(entry.lines.find_by(account: account_604).credit).to eq(400)
      expect(entry.lines.find_by(account: result_account).credit).to eq(600) # a profit
    end

    it "settles a loss on the debit of the result account" do
      book(account_604, account_440, 2000)
      entry = step.perform(user: accountant)[:entry]
      expect(entry.lines.find_by(account: result_account)).to have_attributes(debit: BigDecimal("1400"), credit: 0)
    end

    it "settles an income account that holds a balance on the wrong side too" do
      book(account_440, account_604, 50) # a credit on an expense account
      entry = step.perform(user: accountant)[:entry]
      expect(entry.lines.find_by(account: account_604)).to have_attributes(debit: BigDecimal("0"), credit: BigDecimal("350"))
    end

    it "takes the result account that the entity chose" do
      create(:account, code: "690000", label_fr: "Profit and loss", account_class: 6, account_type: :expense, normal_balance: :debit)
      entity.update!(closing_result_account_code: "690000")
      run.reload
      expect(step.perform(user: accountant)[:entry].lines.joins(:account).where(accounting_accounts: { code: "690000" })).to exist
    end

    it "refuses when the result account does not exist, naming it" do
      result_account.destroy!
      result = step.perform(user: accountant)
      expect(result).to be_failure
      expect(result.message).to include("699000")
    end

    it "makes only one entry however many times it is asked" do
      first = step.perform(user: accountant)[:entry]
      expect { step.perform(user: accountant) }.not_to change(Accounting::JournalEntry, :count)
      expect(step.perform(user: accountant)[:entry]).to eq(first)
    end

    it "validates nothing by itself (criterion 5)" do
      step.perform(user: accountant)
      expect(Accounting::JournalEntry.where(closing_run_id: run.id).pluck(:status).uniq).to eq([ "draft" ])
    end
  end

  describe "after the entries of the earlier steps" do
    let!(:adjustment) do
      entry = create(:journal_entry, :draft, journal: misc, fiscal_year: fiscal_year, entry_date: year_end, closing_run_id: nil, source_type: Accounting::JournalEntry::REVALUATION_SOURCE)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: 100, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: account_440, debit: 0, credit: 100)
      entry.update_columns(closing_run_id: run.id)
      entry
    end

    it "waits while an entry of a regularization or of the revaluation is still a draft, and says so" do
      result = step.perform(user: accountant)
      expect(result).to be_failure
      expect(result.message).to match(/earlier steps/i)
      expect(outcome).to have_attributes(status: :pending)
      expect(outcome.details).to include("waiting_for" => "entries_of_earlier_steps")
    end

    it "includes it once validated" do
      Closing::ValidateEntries.call(run: run, user: accountant)
      entry = step.perform(user: accountant)[:entry]
      expect(entry.lines.find_by(account: account_604).credit).to eq(500) # 400 + 100
    end

    it "makes a draft again when an entry was validated after it was drafted" do
      Closing::ValidateEntries.call(run: run, user: accountant)
      first = step.perform(user: accountant)[:entry]
      late = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: year_end - 1)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: late, account: account_604, debit: 50, credit: 0)
      create(:journal_entry_line, journal_entry: late, account: account_440, debit: 0, credit: 50)
      late.post!

      expect(outcome.details).to include("stale" => true)
      second = step.perform(user: accountant)[:entry]
      expect(second.id).not_to eq(first.id)
      expect(Accounting::JournalEntry.exists?(first.id)).to be(false)
      expect(second.lines.find_by(account: account_604).credit).to eq(550)
    end
  end

  describe "reading" do
    it "is pending while there is something to close, whether the entry is not drafted yet or waits to be validated" do
      expect(outcome).to have_attributes(status: :pending)
      step.perform(user: accountant)
      result = outcome
      expect(result).to have_attributes(status: :pending)
      expect(result.details).to include("draft_entry_id" => be_a(Integer))
    end

    it "is ok once the entry is posted and the income accounts are at zero" do
      step.perform(user: accountant)
      Closing::ValidateEntries.call(run: run, user: accountant)
      expect(outcome).to have_attributes(status: :ok)
      expect(Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year).call.select { |r| %w[expense revenue].include?(r.account_type) && r.code != "699000" }.map(&:balance).uniq).to eq([ 0 ])
    end

    it "is ok at once for a year with nothing to close" do
      other = create(:fiscal_year, status: :pre_closing, year: fiscal_year.year + 1, start_date: year_end + 1, end_date: year_end + 365)
      other_run = Closing::OpenRun.call(fiscal_year: other, user: accountant)[:run]
      expect(Closing::Registry.fetch("closing_entries").new(other_run).evaluate).to have_attributes(status: :ok)
    end
  end

  describe "validating in a batch" do
    it "posts the drafts of the run, for someone who may post, after which the entry is in the ledger" do
      step.perform(user: accountant)
      result = Closing::ValidateEntries.call(run: run, user: accountant)

      expect(result).to be_success, result.message
      expect(result[:posted].size).to eq(1)
      expect(Accounting::JournalEntry.where(closing_run_id: run.id).sole).to be_posted
    end

    it "is refused to someone who may not post (an assistant)" do
      step.perform(user: accountant)
      result = Closing::ValidateEntries.call(run: run, user: assistant)
      expect(result).to be_failure
      expect(Accounting::JournalEntry.where(closing_run_id: run.id).sole).to be_draft
    end

    it "is audited" do
      step.perform(user: accountant)
      Closing::ValidateEntries.call(run: run, user: accountant)
      expect(Accounting::AuditLog.where(auditable_type: "Accounting::ClosingRun", auditable_id: run.id, action: "closing_entries_validated")).to exist
    end

    it "is all or nothing: a refusal on one entry posts none, and the run goes on from there when it is cleared (resuming after an interruption)" do
      step.perform(user: accountant)
      other = create(:journal_entry, :draft, journal: misc, fiscal_year: fiscal_year, entry_date: year_end, closing_run_id: run.id, source_type: Accounting::JournalEntry::CARRY_FORWARD_SOURCE)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: other, account: account_604, debit: 5, credit: 0) # unbalanced: refused
      result = Closing::ValidateEntries.call(run: run, user: accountant)

      expect(result).to be_failure
      expect(Accounting::JournalEntry.where(closing_run_id: run.id).pluck(:status).uniq).to eq([ "draft" ])
      other.destroy!
      expect(Closing::ValidateEntries.call(run: run, user: accountant)).to be_success
      expect(Accounting::JournalEntry.where(closing_run_id: run.id).sole).to be_posted
    end

    it "says there is nothing to validate when there is nothing" do
      expect(Closing::ValidateEntries.call(run: run, user: accountant)).to be_failure
    end

    context "when a lock covers the date of the entry" do
      before do
        step.perform(user: accountant)
        create(:period_lock, kind: :vat, starts_on: year_end.beginning_of_month, ends_on: year_end)
      end

      it "refuses without a controlled window, saying to open one" do
        result = Closing::ValidateEntries.call(run: run, user: accountant)
        expect(result).to be_failure
        expect(result.message).to match(/controlled window/i)
        expect(Accounting::JournalEntry.where(closing_run_id: run.id).sole).to be_draft
      end

      it "posts inside the window an owner opened, and only inside it" do
        Accounting::OpenControlledWindow.call(user: owner, reason: "Closing 2026", purpose: "closing", hours: 2)
        expect(Closing::ValidateEntries.call(run: run, user: accountant)).to be_success
        expect(Accounting::JournalEntry.where(closing_run_id: run.id).sole).to be_posted

        late = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: year_end)
        create(:journal_entry_line, journal_entry: late, account: account_604, debit: 5, credit: 0)
        create(:journal_entry_line, journal_entry: late, account: account_440, debit: 0, credit: 5)
        expect(Accounting::PostJournalEntry.call(entry: late)).to be_failure # the window does not stay open on the books
      end
    end
  end
end
