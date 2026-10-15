require "rails_helper"

# B03c "Clôture": step 17 of the closing (F10) issues a certificate of integrity of the `standard` level for the year, and puts it in the closing file (R20). A certificate that
# cannot be issued does not stop the closing: the closing file says so.
RSpec.describe "Closing: the certificate of integrity" do
  include_context "with_open_fiscal_year"
  include_context "with signing keys directory"

  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:run) { Closing::OpenRun.call(fiscal_year: fiscal_year, user: accountant)[:run] }
  let(:journal) { create(:journal, :sale) }
  let!(:misc) { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let!(:bank) { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:capital) { create(:account, code: "100000", label_fr: "Capital", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:revenue) { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:result_account) { create(:account, code: "699000", label_fr: "Result", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:carry_account) { create(:account, code: "140100", label_fr: "Carried forward", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:next_year) { create(:fiscal_year, status: :pre_closing, year: fiscal_year.year + 1, start_date: fiscal_year.end_date + 1, end_date: ((fiscal_year.end_date + 1) >> 12) - 1) }

  def post(date, debit, credit, amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: debit, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: credit, debit: 0, credit: amount)
    entry.post!
  end

  def step(code) = Closing::Registry.fetch(code).new(run)

  def bundle_files = Accounting::Zipper.read(run.reload.bundle.download)

  before do
    entity.update!(vat_regime: :franchise)
    post(fiscal_year.start_date + 1, bank, capital, 10_000)
    post(fiscal_year.start_date + 20, bank, revenue, 800)
    step("closing_entries").perform(user: accountant)
    Closing::ValidateEntries.call(run: run, user: accountant)
    step("carry_forward").perform(user: accountant)
    Closing::ValidateEntries.call(run: run, user: accountant)
  end

  context "with the feature on and a signing key" do
    before do
      entity.update!(features: entity.features.merge("b03c" => true))
      Ledger::SigningKeys.generate!
    end

    it "issues a standard certificate for the year, and puts it, signed, with its PDF, in the closing file, listed in its manifest" do
      result = step("lock_and_bundle").perform(user: accountant)

      expect(result).to be_success, result.message
      certificate = IntegrityCertificate.last
      expect(certificate).to have_attributes(disclosure_level: "standard", fiscal_year_id: fiscal_year.id, issued_by_id: accountant.id)
      files = bundle_files
      expect(files.keys).to include("integrity_certificate.json", "integrity_certificate.pdf")
      expect(JSON.parse(files["integrity_certificate.json"])["id"]).to eq(certificate.uuid)
      expect(LedgerVerify::Verifier.call(files["integrity_certificate.json"])).to be_pass
      expect(JSON.parse(files["manifest.json"])["files"].map { |f| f["path"] }).to include("integrity_certificate.json", "integrity_certificate.pdf")
    end

    it "is made once: the step done again does not issue another" do
      step("lock_and_bundle").perform(user: accountant)

      expect { step("lock_and_bundle").perform(user: accountant) }.not_to change(IntegrityCertificate, :count)
    end

    it "does not stop the closing when the certificate cannot be issued, and the closing file says why" do
      Ledger::SigningKey.update_all(status: "retired")

      result = step("lock_and_bundle").perform(user: accountant)

      expect(result).to be_success
      expect(IntegrityCertificate.count).to eq(0)
      files = bundle_files
      expect(files.keys).not_to include("integrity_certificate.json")
      expect(JSON.parse(files["manifest.json"])["integrity_certificate"]).to include("issued" => false, "reason" => include("signing key"))
      expect(Accounting::AuditLog.where(action: "closing_certificate_not_issued")).to exist
    end
  end

  it "does nothing about it when the feature is off" do
    entity.update!(features: entity.features.merge("b03c" => false))
    result = step("lock_and_bundle").perform(user: accountant)

    expect(result).to be_success
    expect(bundle_files.keys).not_to include("integrity_certificate.json")
    expect(JSON.parse(bundle_files["manifest.json"])).not_to have_key("integrity_certificate")
  end
end
