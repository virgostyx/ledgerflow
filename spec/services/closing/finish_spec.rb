require "rails_helper"

# F10, steps 17 and 18: the lock, the snapshot and the closing file; the approval that closes the year. Criteria 4, 6, 8 and 9.
RSpec.describe "Closing: lock, snapshot and approval" do
  include_context "with_open_fiscal_year"

  let(:owner)      { create(:user, email: "owner@firm.test").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:accountant) { create(:user, email: "acc@firm.test").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:run) { Closing::OpenRun.call(fiscal_year: fiscal_year, user: accountant)[:run] }
  let(:journal) { create(:journal, :sale) }
  let!(:misc) { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let(:year_end) { fiscal_year.end_date }

  let!(:bank)    { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:capital) { create(:account, code: "100000", label_fr: "Capital", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:revenue) { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:result_account) { create(:account, code: "699000", label_fr: "Result", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:carry_account)  { create(:account, code: "130000", label_fr: "Carried forward", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:next_year) { create(:fiscal_year, status: :pre_closing, year: fiscal_year.year + 1, start_date: year_end + 1, end_date: ((year_end + 1) >> 12) - 1) }

  def step(code) = Closing::Registry.fetch(code).new(run)

  def post(date, debit, credit, amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: debit, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: credit, debit: 0, credit: amount)
    entry.post!
  end

  before { entity.update!(vat_regime: :franchise) } # no VAT periods to file: step 5 reads ok

  describe "17. lock and closing file" do
    before do
      post(fiscal_year.start_date + 1, bank, capital, 10_000)
      post(fiscal_year.start_date + 20, bank, revenue, 800)
    end

    def run_to_17
      step("closing_entries").perform(user: accountant)
      Closing::ValidateEntries.call(run: run, user: accountant)
      step("carry_forward").perform(user: accountant)
      Closing::ValidateEntries.call(run: run, user: accountant)
    end

    it "refuses while an earlier blocking step is not settled, naming it" do
      result = step("lock_and_bundle").perform(user: accountant)
      expect(result).to be_failure
      expect(result.message).to match(/step/i)
    end

    context "with every earlier step settled" do
      before { run_to_17 }

      it "locks the year and its months, takes the snapshot with its hash, and makes the closing file with its manifest" do
        result = step("lock_and_bundle").perform(user: accountant)
        expect(result).to be_success, result.message

        expect(Accounting::PeriodLock.in_force.where(kind: :fiscal_year).where("starts_on <= ? AND ends_on >= ?", fiscal_year.start_date, year_end)).to exist
        expect(Accounting::PeriodLock.in_force.where(kind: :accounting).count).to eq(12)
        snapshot = run.reload.snapshot
        expect(snapshot.sha256).to match(/\A\h{64}\z/)
        expect(snapshot.content.keys).to include("trial_balance", "balance_sheet", "income_statement")
        expect(run.bundle).to be_attached
        manifest = JSON.parse(Accounting::Zipper.read(run.bundle.download).fetch("manifest.json"))
        expect(manifest["files"]).not_to be_empty
      end

      it "makes a snapshot that reads back with the same hash (criterion 9)" do
        step("lock_and_bundle").perform(user: accountant)
        snapshot = Accounting::ClosingSnapshot.find(run.snapshot.id)
        expect(snapshot).to be_intact
        expect(Accounting::ClosingSnapshot.fingerprint(snapshot.content)).to eq(snapshot.sha256)
      end

      it "is no longer intact when the content is touched" do
        step("lock_and_bundle").perform(user: accountant)
        snapshot = run.snapshot
        snapshot.update_columns(content: snapshot.content.merge("trial_balance" => []))
        expect(snapshot.reload).not_to be_intact
      end

      it "refuses any entry in the year afterwards, including by direct SQL (criterion 6)" do
        step("lock_and_bundle").perform(user: accountant)
        late = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 100)
        create(:journal_entry_line, journal_entry: late, account: bank, debit: 5, credit: 0)
        create(:journal_entry_line, journal_entry: late, account: revenue, debit: 0, credit: 5)
        expect(Accounting::PostJournalEntry.call(entry: late)).to be_failure

        sql = "UPDATE accounting_journal_entries SET status = 1, reference = 'SQL-1' WHERE id = #{late.id}"
        expect { ApplicationRecord.connection.execute(sql) }.to raise_error(ActiveRecord::StatementInvalid, /locked period/)
      end

      it "is done once the lock, the snapshot and the file are there, and does nothing twice" do
        step("lock_and_bundle").perform(user: accountant)
        expect(step("lock_and_bundle").evaluate).to have_attributes(status: :ok)
        expect { step("lock_and_bundle").perform(user: accountant) }.not_to change(Accounting::ClosingSnapshot, :count)
      end

      it "is pending before it ran" do
        expect(step("lock_and_bundle").evaluate).to have_attributes(status: :pending)
      end
    end
  end

  describe "18. approval" do
    before do
      post(fiscal_year.start_date + 1, bank, capital, 10_000)
      step("closing_entries").perform(user: accountant)
      Closing::ValidateEntries.call(run: run, user: accountant)
      step("carry_forward").perform(user: accountant)
      Closing::ValidateEntries.call(run: run, user: accountant)
      expect(step("lock_and_bundle").perform(user: accountant)).to be_success
    end

    it "is for an owner: an accountant may not approve" do
      result = Closing::Approve.call(run: run, user: accountant, comment: "OK")
      expect(result).to be_failure
      expect(run.reload).not_to be_closed
    end

    it "needs a comment" do
      expect(Closing::Approve.call(run: run, user: owner, comment: "")).to be_failure
    end

    it "closes the year, opens the next one, records who approved and when" do
      result = Closing::Approve.call(run: run, user: owner, comment: "Approved after review")
      expect(result).to be_success, result.message

      expect(run.reload).to have_attributes(status: "closed", approved_by: owner, closed_by: owner)
      expect(run.approved_at).to be_present
      expect(run.steps.find_by(code: "approval")).to have_attributes(status: "done", comment: "Approved after review", completed_by: owner)
      expect(fiscal_year.reload).to have_attributes(status: "closed")
      expect(fiscal_year.closed_at).to be_present
      expect(next_year.reload.status).to eq("open")
    end

    it "does not close while a blocking step is not settled (criterion 4)" do
      create(:bank_account) # a bank account with no reconciliation frozen on the last day: step 3 blocks
      result = Closing::Approve.call(run: run, user: owner, comment: "Go")
      expect(result).to be_failure
      expect(result.message).to match(/3\. Bank/)
      expect(fiscal_year.reload).to be_open
      expect(run.reload).not_to be_closed
    end

    it "is audited" do
      Closing::Approve.call(run: run, user: owner, comment: "Approved")
      expect(Accounting::AuditLog.where(auditable_type: "Accounting::ClosingRun", auditable_id: run.id, action: "closing_approved")).to exist
    end

    describe "with four eyes (criterion 8)" do
      before do
        entity.update!(four_eyes: true)
        run.reload # the run reads the entity as it stands now
      end

      it "refuses the owner who prepared the closing" do
        run.update!(opened_by: owner) # the owner opens the run: the preparation is theirs
        result = Closing::Approve.call(run: run, user: owner, comment: "Approved")
        expect(result).to be_failure
        expect(result.message).to match(/prepared/i)
      end

      it "also refuses the owner who did one of the steps" do
        run.steps.find_by(code: "carry_forward").update!(completed_by: owner)
        expect(Closing::Approve.call(run: run, user: owner, comment: "Approved")).to be_failure
      end

      it "accepts another owner" do
        other = create(:user, email: "other-owner@firm.test").tap { |u| create(:user_entity, :admin, user: u, entity: entity) }
        expect(Closing::Approve.call(run: run, user: other, comment: "Approved")).to be_success
      end
    end

    it "lets the owner who prepared approve when the entity does not ask for four eyes" do
      run.update!(opened_by: owner)
      expect(Closing::Approve.call(run: run, user: owner, comment: "Approved")).to be_success
    end
  end

  describe "performing a step" do
    it "does the work of an action step for someone who may prepare, and records who did it" do
      result = Closing::PerformStep.call(run: run, code: "preparation", user: accountant)
      expect(result).to be_success, result.message
      expect(run.steps.find_by(code: "preparation")).to have_attributes(completed_by: accountant, status: "done")
    end

    it "is refused to someone who may not prepare a closing" do
      assistant = create(:user).tap { |u| create(:user_entity, :assistant, user: u, entity: entity) }
      expect(Closing::PerformStep.call(run: run, code: "preparation", user: assistant)).to be_failure
    end

    it "is refused for a step that is not an action, and for a run that is closed" do
      expect(Closing::PerformStep.call(run: run, code: "bank", user: accountant)).to be_failure
      run.update!(status: :closed)
      expect(Closing::PerformStep.call(run: run, code: "preparation", user: accountant)).to be_failure
    end
  end
end
