require "rails_helper"

# Every check: create the anomaly, see it detected, correct it, see it gone (R19 acceptance criterion 1);
# a clean dataset raises nothing (criterion 2).
RSpec.describe "Accounting::Consistency checks", type: :service do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:bank)      { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:customers) { create(:account, code: "400000", label_fr: "Customers", account_class: 4, account_type: :asset, normal_balance: :debit, reconcilable: true) }
  let!(:suppliers) { create(:account, code: "440000", label_fr: "Suppliers", account_class: 4, account_type: :liability, normal_balance: :credit, reconcilable: true) }
  let!(:sales)     { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:expense)   { create(:account, code: "600000", label_fr: "Purchases", account_class: 6, account_type: :expense, normal_balance: :debit) }

  def post(*lines, on: fiscal_year.start_date + 10, publish: true, jr: journal)
    entry = create(:journal_entry, :draft, journal: jr, fiscal_year: fiscal_year, entry_date: on)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    lines.each { |account, debit, credit, extra| create(:journal_entry_line, journal_entry: entry, account: account, debit: debit, credit: credit, **(extra || {})) }
    entry.post! if publish
    entry
  end

  def found(check_class) = check_class.new.call
  Checks = Accounting::Consistency::Checks

  shared_examples "detects then clears" do |klass_name|
    it "is detected once the anomaly exists and disappears once corrected" do
      klass = Accounting::Consistency::Checks.const_get(klass_name)
      expect(found(klass)).to be_empty, "expected a clean start, got #{found(klass).map(&:message)}"
      create_anomaly
      findings = found(klass)
      expect(findings).not_to be_empty
      expect(findings).to all(have_attributes(check_id: klass.check_id, severity: klass.severity, fingerprint: match(/\A\h{64}\z/)))
      correct_anomaly
      expect(found(klass)).to be_empty
    end
  end

  describe "C01 unbalanced entry" do
    let(:entry) { post([ bank, 100, 0 ], [ sales, 0, 90 ], publish: false) }
    def create_anomaly = entry
    def correct_anomaly = create(:journal_entry_line, journal_entry: entry, account: sales, debit: 0, credit: 10)
    include_examples "detects then clears", :C01UnbalancedEntry
  end

  describe "C02 entry outside its fiscal year" do
    let(:entry) { post([ bank, 10, 0 ], [ sales, 0, 10 ], publish: false) }
    def create_anomaly = entry.update_columns(entry_date: fiscal_year.start_date - 5)
    def correct_anomaly = entry.update_columns(entry_date: fiscal_year.start_date + 5)
    before { entry }
    include_examples "detects then clears", :C02EntryOutsideFiscalYear
  end

  describe "C03 numbering gap" do
    let!(:first)  { post([ bank, 10, 0 ], [ sales, 0, 10 ]) }
    let!(:second) { post([ bank, 10, 0 ], [ sales, 0, 10 ]) }
    let(:prefix)  { "#{journal.sequence_prefix}#{fiscal_year.year}/" }
    before do
      first.update_columns(reference: "#{prefix}0001")
      second.update_columns(reference: "#{prefix}0002")
    end
    def create_anomaly = second.update_columns(reference: "#{prefix}0003")
    def correct_anomaly = second.update_columns(reference: "#{prefix}0002")
    include_examples "detects then clears", :C03NumberingGap
  end

  describe "C04 inverted balance" do
    let(:credit_entry) { post([ bank, 100, 0 ], [ customers, 0, 100 ]) }
    def create_anomaly = credit_entry
    def correct_anomaly = post([ customers, 100, 0 ], [ sales, 0, 100 ])
    include_examples "detects then clears", :C04InvertedBalance
  end

  describe "C05 probable duplicate" do
    let(:partner) { create(:partner, :supplier) }
    let(:one) { create(:invoice, :posted, partner: partner, invoice_type: :supplier, fiscal_year: fiscal_year, invoice_date: Date.current) }
    let(:two) { create(:invoice, :posted, partner: partner, invoice_type: :supplier, fiscal_year: fiscal_year, invoice_date: Date.current) }
    def create_anomaly
      one.update_columns(external_ref: "F-1", total_incl_vat: 121)
      two.update_columns(external_ref: "F-1", total_incl_vat: 121)
    end
    def correct_anomaly = two.update_columns(status: Accounting::Invoice.statuses[:cancelled])
    include_examples "detects then clears", :C05ProbableDuplicate
  end

  describe "C06 line on an archived account" do
    let(:archived) { create(:account, code: "613000", label_fr: "Old", account_class: 6, account_type: :expense, normal_balance: :debit) }
    before { post([ archived, 10, 0 ], [ bank, 0, 10 ]) }
    def create_anomaly = archived.update_columns(active: false)
    def correct_anomaly = archived.update_columns(active: true)
    include_examples "detects then clears", :C06InactiveAccountLine
  end

  describe "C07 lettered group that does not net to zero" do
    let(:entry) { post([ customers, 100, 0 ], [ sales, 0, 100 ]) }
    let(:payment) { post([ bank, 60, 0 ], [ customers, 0, 60 ]) }
    let(:lettering) { Accounting::Lettering.create!(account: customers, code: "AA", lettered_on: Date.current) }
    def create_anomaly
      entry.lines.find_by(account: customers).update_columns(lettering_id: lettering.id)
      payment.lines.find_by(account: customers).update_columns(lettering_id: lettering.id)
    end
    def correct_anomaly = payment.lines.find_by(account: customers).update_columns(credit: 100)
    include_examples "detects then clears", :C07UnbalancedLettering
  end

  describe "C09 VAT base × rate" do
    let(:invoice) { create(:invoice, :posted, invoice_type: :customer, fiscal_year: fiscal_year) }
    before { create(:invoice_line, invoice: invoice, account: sales).update_columns(subtotal_excl_vat: 100, vat_rate: 21) }
    def create_anomaly = invoice.update_columns(vat_amount: 30)
    def correct_anomaly = invoice.update_columns(vat_amount: 21)
    before { invoice.update_columns(vat_amount: 21) }
    include_examples "detects then clears", :C09VatBaseRate
  end

  describe "C11 invariants" do
    let(:entry) { post([ bank, 100, 0 ], [ sales, 0, 100 ]) }
    def create_anomaly = entry.lines.find_by(account: sales).update_columns(credit: 90)
    def correct_anomaly = entry.lines.find_by(account: sales).update_columns(credit: 100)
    before { entry }
    include_examples "detects then clears", :C11Invariants

    it "names the invariant that failed" do
      create_anomaly
      expect(found(Checks::C11Invariants).map { |f| f.data[:invariant] }).to include("I2")
    end
  end

  describe "C12 document date far from the accounting date" do
    let(:invoice) { create(:invoice, :posted, fiscal_year: fiscal_year, invoice_date: fiscal_year.start_date + 5) }
    let(:entry)   { post([ bank, 10, 0 ], [ sales, 0, 10 ], on: fiscal_year.start_date + 10) }
    before { invoice.update_columns(journal_entry_id: entry.id) }
    def create_anomaly = invoice.update_columns(invoice_date: fiscal_year.start_date - 200)
    def correct_anomaly = invoice.update_columns(invoice_date: fiscal_year.start_date + 5)
    include_examples "detects then clears", :C12DateGap
  end

  describe "C13 account on no rubric" do
    let(:odd) { create(:account, code: "590000", label_fr: "Odd", account_class: 5, account_type: :asset, normal_balance: :debit) }
    def create_anomaly = post([ odd, 50, 0 ], [ bank, 0, 50 ])
    def correct_anomaly = post([ bank, 50, 0 ], [ odd, 0, 50 ])
    include_examples "detects then clears", :C13UnmappedAccount
  end

  describe "C14 customer without a valid VAT number" do
    let(:partner) { create(:partner, name: "No VAT", vat_number: nil, country: "BE") }
    def create_anomaly
      create(:invoice, :posted, partner: partner, invoice_type: :customer, vat_treatment: :domestic, fiscal_year: fiscal_year)
        .update_columns(subtotal_excl_vat: 500, vat_amount: 105, total_incl_vat: 605)
    end
    def correct_anomaly = partner.update!(vat_number: "BE0403170701")
    include_examples "detects then clears", :C14CustomerVatNumber
  end

  describe "C16 fixed-asset register vs ledger" do
    let!(:equipment) { create(:account, code: "240200", label_fr: "IT", account_class: 2, account_type: :asset, normal_balance: :debit) }
    let!(:accumulated) { create(:account, code: "249000", label_fr: "Acc", account_class: 2, account_type: :asset, normal_balance: :credit) }
    let!(:expense_dep) { create(:account, code: "630200", label_fr: "Dep", account_class: 6, account_type: :expense, normal_balance: :debit) }
    let(:asset) { create(:fixed_asset, :depreciable, acquisition_date: fiscal_year.start_date + 30, in_service_date: fiscal_year.start_date + 30) }
    def create_anomaly = asset # registered, but never booked
    def correct_anomaly = post([ equipment, 12_000, 0 ], [ bank, 0, 12_000 ])
    include_examples "detects then clears", :C16FixedAssetRegister
  end

  describe "C17 regularization without a reversal" do
    let!(:misc) { create(:journal, journal_type: :misc) }
    let!(:a490) { create(:account, code: "490100", label_fr: "Deferred", account_class: 4, account_type: :asset, normal_balance: :debit) }
    let(:accrual) { create(:accrual, fiscal_year: fiscal_year, pl_account: expense, accrual_account: a490, period_start: fiscal_year.end_date - 30, period_end: fiscal_year.end_date + 300) }
    def create_anomaly = Accounting::BookAccrual.call(accrual: accrual)
    def correct_anomaly = accrual.reload.update_columns(reversal_entry_id: accrual.journal_entry_id)
    include_examples "detects then clears", :C17AccrualWithoutReversal
  end

  describe "a clean dataset" do
    it "raises nothing at all" do
      post([ bank, 5000, 0 ], [ create(:account, code: "100000", label_fr: "Capital", account_class: 1, account_type: :equity, normal_balance: :credit), 0, 5000 ])
      post([ customers, 100, 0 ], [ sales, 0, 100 ])
      post([ expense, 40, 0 ], [ suppliers, 0, 40 ])
      all = Accounting::Consistency::Check.registry.flat_map { |check| check.new.call }
      expect(all.map(&:message)).to eq([])
    end
  end
end
