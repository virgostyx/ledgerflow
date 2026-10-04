require "rails_helper"

# F10, the steps that do something: preparation (the next year), fixed assets, accruals, revaluation. Each is read live, and does its work idempotently.
RSpec.describe "Closing actions" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:run) { Closing::OpenRun.call(fiscal_year: fiscal_year, user: user)[:run] }
  let!(:misc) { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let(:year_end) { fiscal_year.end_date }

  def step(code) = Closing::Registry.fetch(code).new(run)
  def outcome(code) = step(code).evaluate

  describe "1. preparation" do
    it "is pending while the next fiscal year does not exist" do
      expect(outcome("preparation")).to have_attributes(status: :pending)
    end

    it "creates the next year on request: the following twelve months, waiting (not open while this one is), and is then ok" do
      result = step("preparation").perform(user: user)
      expect(result).to be_success

      following = Accounting::FiscalYear.find_by!(start_date: year_end + 1)
      expect(following).to have_attributes(year: fiscal_year.year + 1, end_date: ((year_end + 1) >> 12) - 1, status: "pre_closing")
      expect(outcome("preparation")).to have_attributes(status: :ok)
    end

    it "does nothing the second time" do
      step("preparation").perform(user: user)
      expect { step("preparation").perform(user: user) }.not_to change(Accounting::FiscalYear, :count)
    end

    it "is blocked for a year that is already closed" do
      run
      fiscal_year.update_columns(status: Accounting::FiscalYear.statuses[:closed])
      expect(outcome("preparation")).to have_attributes(status: :blocked)
    end

    it "makes a next year as long as the first one for a year that is not twelve months" do
      fiscal_year.update!(start_date: Date.new(fiscal_year.year, 7, 1), end_date: Date.new(fiscal_year.year + 1, 6, 30))
      step("preparation").perform(user: user)
      following = Accounting::FiscalYear.find_by!(start_date: Date.new(fiscal_year.year + 1, 7, 1))
      expect(following.end_date).to eq(Date.new(fiscal_year.year + 2, 6, 30))
    end
  end

  describe "6. fixed assets" do
    let!(:asset_account) { create(:account, code: "240200", label_fr: "IT equipment", account_class: 2) }
    let!(:expense) { create(:account, code: "630200", label_fr: "Depreciation", account_class: 6) }
    let!(:accumulated) { create(:account, code: "249000", label_fr: "Accumulated", account_class: 2) }

    # The asset, and the entry that booked its acquisition on its account: the register and the ledger then agree (I10).
    def asset
      created = create(:fixed_asset, :depreciable, asset_account: asset_account, acquisition_date: fiscal_year.start_date + 30, in_service_date: fiscal_year.start_date + 40)
      acquisition = create(:journal_entry, :draft, journal: create(:journal, :purchase), fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 30)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: acquisition, account: asset_account, debit: 12_000, credit: 0)
      create(:journal_entry_line, journal_entry: acquisition, account: account_440, debit: 0, credit: 12_000)
      acquisition.post!
      created
    end

    it "is ok with nothing to depreciate" do
      expect(outcome("fixed_assets")).to have_attributes(status: :ok)
    end

    it "is pending while an asset has depreciation to book, and ok once the step has booked it" do
      asset
      result = outcome("fixed_assets")
      expect(result).to have_attributes(status: :pending)
      expect(result.details).to include("to_book" => 1)

      expect(step("fixed_assets").perform(user: user)).to be_success
      expect(outcome("fixed_assets")).to have_attributes(status: :ok)
      expect(Accounting::DepreciationEntry.where(fiscal_year: fiscal_year).count).to eq(1)
    end

    it "books nothing more the second time" do
      asset
      step("fixed_assets").perform(user: user)
      expect { step("fixed_assets").perform(user: user) }.not_to change(Accounting::DepreciationEntry, :count)
    end
  end

  describe "7. accruals" do
    let!(:accrual) { create(:accrual, fiscal_year: fiscal_year, period_start: year_end - 30, period_end: year_end + 335) }
    before { step("preparation").perform(user: user) } # the next year must exist for the reversal

    it "is pending while a regularization is not booked, validated and reversed" do
      result = outcome("accruals")
      expect(result).to have_attributes(status: :pending)
      expect(result.details).to include("unbooked" => 1)
    end

    it "books it and drafts its reversal when the step does its work, then waits for the entry to be validated" do
      expect(step("accruals").perform(user: user)).to be_success
      accrual.reload
      expect(accrual.journal_entry).to be_draft
      expect(accrual.reversal_entry).to be_present
      expect(outcome("accruals")).to have_attributes(status: :pending)
      expect(outcome("accruals").details).to include("drafts" => 1)
    end

    it "is ok once the entry is validated and the books agree with the register (I11)" do
      step("accruals").perform(user: user)
      Accounting::PostJournalEntry.call!(entry: accrual.reload.journal_entry)
      expect(outcome("accruals")).to have_attributes(status: :ok)
    end

    it "is ok with no regularization at all" do
      accrual.destroy!
      expect(outcome("accruals")).to have_attributes(status: :ok)
    end

    it "does not book twice" do
      step("accruals").perform(user: user)
      expect { step("accruals").perform(user: user) }.not_to change(Accounting::JournalEntry, :count)
    end
  end

  describe "12. revaluation" do
    let!(:unrealized) { create(:account, code: "499100", label_fr: "Unrealized losses", account_class: 4, account_type: :liability, normal_balance: :credit) }
    let!(:purchase) { create(:journal, :purchase, default_account: account_440) }
    let!(:supplier) { create(:partner, :supplier, :with_iban, external_ref: "S1") }

    def usd_payable
      Accounting::ExternalInvoice.upsert(external_ref: "U1", partner_external_ref: "S1", invoice_type: "supplier", invoice_date: fiscal_year.start_date.to_s,
                                         currency: "USD", exchange_rate: "1.11111111",
                                         lines: [ { account_code: "604000", description: "Work", quantity: "1", unit_price: "1000", vat_rate: "0" } ])
    end

    def closing_rate(value) = Accounting::ExchangeRate.create!(currency: "USD", rate_date: year_end, rate: value, rate_type: :closing, source: "manual")

    it "is ok with no foreign balance" do
      expect(outcome("revaluation")).to have_attributes(status: :ok)
    end

    it "is blocked without a closing rate, naming the currency" do
      usd_payable
      result = outcome("revaluation")
      expect(result).to have_attributes(status: :blocked)
      expect(result.details).to include("missing_rates" => [ "USD" ])
    end

    it "is pending when there is a loss to book, generates the draft entry on request, and is ok once that entry is posted" do
      usd_payable
      closing_rate("1.05263158")
      expect(outcome("revaluation")).to have_attributes(status: :pending)

      expect(step("revaluation").perform(user: user)).to be_success
      draft = Fx::Revalue.existing(fiscal_year: fiscal_year)
      expect(draft).to be_draft
      expect(outcome("revaluation")).to have_attributes(status: :pending)
      expect(outcome("revaluation").details).to include("draft_entry_id" => draft.id)

      Accounting::PostJournalEntry.call!(entry: draft)
      expect(outcome("revaluation")).to have_attributes(status: :ok)
    end

    it "is ok when the closing rate leaves nothing to book (a gain, which the entity does not book)" do
      usd_payable
      closing_rate("1.17647059")
      expect(outcome("revaluation")).to have_attributes(status: :ok)
    end
  end
end
