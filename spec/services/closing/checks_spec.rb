require "rails_helper"

# F10, the checks of the closing: each one reads the books as they are now, with a passing case and a blocking one.
RSpec.describe "Closing checks" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:run) { Closing::OpenRun.call(fiscal_year: fiscal_year, user: user)[:run] }
  let(:journal) { create(:journal, :purchase) }
  let(:year_end) { fiscal_year.end_date }

  def outcome(code) = Closing::Registry.fetch(code).new(run).evaluate

  def entry(status: :posted, date: fiscal_year.start_date + 10, debit_account: account_604, credit_account: account_440, amount: 100, partner: nil, **attrs)
    e = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date, **attrs)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: e, account: debit_account, partner: partner, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: e, account: credit_account, partner: partner, debit: 0, credit: amount)
    e.post! if status == :posted
    e
  end

  describe "2. entries complete" do
    it "is ok with nothing in draft" do
      entry
      expect(outcome("entries_complete")).to have_attributes(status: :ok)
    end

    it "is blocked by an entry in draft, counted" do
      entry(status: :draft)
      result = outcome("entries_complete")
      expect(result).to have_attributes(status: :blocked)
      expect(result.details).to include("drafts" => 1)
    end

    it "does not count the drafts the closing itself made" do
      run
      entry(status: :draft, closing_run_id: run.id)
      expect(outcome("entries_complete")).to have_attributes(status: :ok)
    end

    it "warns of a task of the type 'closing' still open (F08), to acknowledge with a comment" do
      Accounting::Task.create!(title: "Check the stock count", kind: :closing)
      result = outcome("entries_complete")
      expect(result).to have_attributes(status: :warning)
      expect(result.details).to include("tasks" => 1)
    end

    it "ignores a closed task" do
      Accounting::Task.create!(title: "Done", kind: :closing, status: :done)
      expect(outcome("entries_complete")).to have_attributes(status: :ok)
    end
  end

  describe "3. bank" do
    let!(:bank_account) { create(:bank_account) }

    def freeze(on: year_end)
      result = Accounting::BankReconciliationQuery.new(bank_account: bank_account, as_of: on).call
      Accounting::BankReconciliationReport.record!(bank_account: bank_account, as_of: on, result: { gap: result.gap.to_s })
    end

    it "is blocked while a bank account has no frozen reconciliation on the last day" do
      result = outcome("bank")
      expect(result).to have_attributes(status: :blocked)
      expect(result.details["accounts"].first).to include("frozen" => false)
    end

    it "is ok once every active bank account has one, with a zero gap" do
      freeze
      expect(outcome("bank")).to have_attributes(status: :ok)
    end

    it "is blocked when a reconciliation frozen on another day does not count" do
      freeze(on: year_end - 1)
      expect(outcome("bank")).to have_attributes(status: :blocked)
    end

    it "is blocked when the gap is not zero any more, whatever was frozen: a statement closes on a balance that the books do not have" do
      freeze
      batch = Accounting::ImportBatch.create!(parser: "coda", file_sha256: "gap", result: "imported")
      Accounting::BankStatement.create!(bank_account: bank_account, import_batch: batch, old_balance: 0, old_balance_date: year_end, new_balance: 500, new_balance_date: year_end)
      result = outcome("bank")
      expect(result).to have_attributes(status: :blocked)
      expect(result.details["accounts"].first).to include("frozen" => true, "gap_now" => "-500.0")
    end

    it "ignores an inactive bank account" do
      bank_account.update!(active: false)
      expect(outcome("bank")).to have_attributes(status: :ok)
    end
  end

  describe "4. partners" do
    let(:partner) { create(:partner, :supplier, payment_terms_days: 0) }
    before { account_440.update!(account_type: :liability, normal_balance: :credit) } # a supplier account is in credit, as in the chart

    it "is ok when the aged balance is the balance of the account and no balanced group is left unlettered" do
      entry(partner: partner, amount: 100)
      expect(outcome("partners")).to have_attributes(status: :ok)
    end

    it "is blocked by a balanced group of open lines that nobody lettered" do
      entry(partner: partner, amount: 100)
      entry(debit_account: account_440, credit_account: account_604, partner: partner, amount: 100) # the opposite line, same amount
      result = outcome("partners")
      expect(result).to have_attributes(status: :blocked)
      expect(result.details).to include("balanced_groups" => 1)
    end
  end

  describe "5. VAT" do
    it "is ok for an entity under the VAT franchise" do
      entity.update!(vat_regime: :franchise)
      expect(outcome("vat")).to have_attributes(status: :ok)
    end

    it "is blocked while a period of the year has no declaration submitted" do
      entity.update!(vat_regime: :normal, vat_filing_frequency: :quarterly)
      result = outcome("vat")
      expect(result).to have_attributes(status: :blocked)
      expect(result.details["periods"]).to be_present
    end

    it "is blocked by a declaration that is submitted but whose period is not locked" do
      entity.update!(vat_regime: :normal, vat_filing_frequency: :quarterly)
      each_quarter { |from, to| create(:vat_declaration, fiscal_year: fiscal_year, period_start: from, period_end: to, status: :submitted) }
      result = outcome("vat")
      expect(result).to have_attributes(status: :blocked)
      expect(result.details["periods"].map { |p| p["locked"] }.uniq).to eq([ false ])
    end

    it "is ok once every period is submitted and locked" do
      entity.update!(vat_regime: :normal, vat_filing_frequency: :quarterly)
      each_quarter do |from, to|
        create(:vat_declaration, fiscal_year: fiscal_year, period_start: from, period_end: to, status: :submitted)
        create(:period_lock, kind: :vat, starts_on: from, ends_on: to)
      end
      expect(outcome("vat")).to have_attributes(status: :ok)
    end

    def each_quarter
      4.times { |i| from = fiscal_year.start_date >> (3 * i); yield from, (from >> 3) - 1 }
    end
  end

  describe "11. suspense accounts" do
    let!(:suspense) { create(:account, code: "499000", label_fr: "Suspense", account_class: 4, account_type: :asset, normal_balance: :debit) }

    it "is ok when the suspense and link accounts are at zero" do
      expect(outcome("suspense")).to have_attributes(status: :ok)
    end

    it "is blocked by a balance on a suspense account, naming it" do
      entry(debit_account: suspense, credit_account: account_604, amount: 30)
      result = outcome("suspense")
      expect(result).to have_attributes(status: :blocked)
      expect(result.details["accounts"]).to include(a_hash_including("code" => "499000", "balance" => "30.0"))
    end

    it "also looks at the transit account of internal transfers (580000)" do
      transit = create(:account, code: "580000", label_fr: "Transfers", account_class: 5, account_type: :asset, normal_balance: :debit)
      entry(debit_account: transit, credit_account: account_604, amount: 10)
      expect(outcome("suspense")).to have_attributes(status: :blocked)
    end
  end

  describe "13. consistency" do
    it "is ok when the checks of R19 find nothing blocking" do
      entry
      expect(outcome("consistency")).to have_attributes(status: :ok)
    end

    it "is blocked by a blocking anomaly of R19, and warns of the others until acknowledged" do
      entry
      allow(Accounting::Consistency::Runner).to receive(:call).and_wrap_original do |original, **args|
        run = original.call(**args)
        Accounting::ConsistencyFinding.create!(run_id: run.id, check_id: "C04", severity: "blocking", subject_type: "Accounting::Account", subject_id: account_604.id,
                                               message: "Inverted balance", data: {}, fingerprint: "fp-blocking")
        run.update!(counts: run.counts.merge("blocking" => 1))
        run
      end
      expect(outcome("consistency")).to have_attributes(status: :blocked)
    end

    it "runs the invariants of the year (I2, I6, I7, I11)" do
      entry
      expect(Accounting::Consistency::Runner).to receive(:call).and_call_original
      outcome("consistency")
    end
  end
end
