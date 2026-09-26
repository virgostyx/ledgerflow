require "rails_helper"

RSpec.describe Accounting::ClosingChecklist do
  include_context "with_open_fiscal_year"

  let(:as_of)   { fiscal_year.end_date }
  let(:journal) { create(:journal, :purchase) }
  let!(:bank)      { create(:account, code: "550000", label_fr: "Banque", account_type: :asset, normal_balance: :debit, account_class: 5) }
  let!(:capital)   { create(:account, code: "101000", label_fr: "Capital", account_type: :equity, normal_balance: :credit, account_class: 1) }

  def checklist(as_of: self.as_of) = described_class.new(fiscal_year: fiscal_year, as_of: as_of).call
  def check(key, list = checklist) = list.checks.find { |c| c.key == key }

  def post(debit, credit, amount, on: fiscal_year.start_date + 5)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: on)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: debit,  debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: credit, debit: 0, credit: amount)
    entry.post!
    entry
  end

  before { post(bank, capital, 1_000) }

  it "is all clear for a year with nothing to do (under the franchise, which has no VAT to declare)" do
    entity.update!(vat_regime: :franchise)
    list = checklist
    expect(list.checks.map(&:status).uniq).to eq([ :ok ]).or eq(%i[ok info])
    expect(list).not_to be_blocking
    expect(list.warnings_count).to eq(0)
  end

  describe "what blocks the closing" do
    it "flags entries still in draft, with their number" do
      create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 9)
      expect(check(:draft_entries)).to have_attributes(status: :blocking, count: 1)
      expect(checklist).to be_blocking
    end

    it "flags depreciation still to book" do
      allow(Accounting::PostDepreciation).to receive(:pending).with(fiscal_year).and_return([ [ build_stubbed(:fixed_asset), 100 ] ])
      expect(check(:depreciation)).to have_attributes(status: :blocking, count: 1)
    end

    it "flags a balance sheet that does not balance when no account is to blame" do
      stub = Accounting::AnnualAccounts::Report.new(fiscal_year: fiscal_year, rows_by_statement: {}, difference: BigDecimal("50"), unmapped: [])
      allow_any_instance_of(Accounting::AnnualAccounts).to receive(:call).and_return(stub)
      expect(check(:balance)).to have_attributes(status: :blocking)
    end

    it "only warns when accounts fit no heading of the model, which may explain the difference" do
      odd = Accounting::AnnualAccounts::Unmapped.new(code: "590000", label: "Odd", balance: 50)
      stub = Accounting::AnnualAccounts::Report.new(fiscal_year: fiscal_year, rows_by_statement: {}, difference: BigDecimal("50"), unmapped: [ odd ])
      allow_any_instance_of(Accounting::AnnualAccounts).to receive(:call).and_return(stub)
      expect(check(:balance)).to have_attributes(status: :warning, count: 1)
      expect(checklist).not_to be_blocking
    end
  end

  describe "the warnings" do
    it "counts draft invoices dated in the year" do
      create(:invoice, :draft, fiscal_year: fiscal_year)
      create(:invoice, :draft, fiscal_year: fiscal_year)
      expect(check(:draft_invoices)).to have_attributes(status: :warning, count: 2)
    end

    it "counts the bank transactions of the year that are not reconciled, ignoring those of other years and the settled ones" do
      account = create(:bank_account)
      attrs = { bank_account: account, amount: 10, description: "x" }
      create(:bank_transaction, transaction_date: fiscal_year.start_date + 3, status: :pending, **attrs)
      create(:bank_transaction, transaction_date: fiscal_year.start_date + 4, status: :pending, **attrs)
      create(:bank_transaction, transaction_date: fiscal_year.start_date + 5, status: :reconciled, **attrs)
      create(:bank_transaction, transaction_date: fiscal_year.start_date + 6, status: :ignored, **attrs)
      create(:bank_transaction, transaction_date: fiscal_year.end_date + 3, status: :pending, **attrs)

      expect(check(:bank)).to have_attributes(status: :warning, count: 2)
    end

    it "counts the customers who owe money for more than 90 days at the year end" do
      old = create(:invoice, :posted, fiscal_year: fiscal_year, due_date: fiscal_year.end_date - 100)
      stub = [ Accounting::AgedBalanceQuery::Row.new(partner_name: "A", over_90: BigDecimal("300"), total: BigDecimal("300")) ]
      allow_any_instance_of(Accounting::AgedBalanceQuery).to receive(:call).and_return(stub)
      expect(check(:overdue_receivables)).to have_attributes(status: :warning, count: 1)
      expect(old).to be_persisted
    end

    it "counts the unallocated payments and credit notes that stayed unused" do
      row = Accounting::StaleCreditsQuery::Row.new(partner_name: "A", reference: "R", entry_date: as_of - 200, amount: 10, age_days: 200)
      allow_any_instance_of(Accounting::StaleCreditsQuery).to receive(:call).and_return([ row ])
      expect(check(:stale_credits)).to have_attributes(status: :warning, count: 2) # customers and suppliers
    end
  end

  describe "VAT" do
    let(:today) { Date.new(fiscal_year.year, 9, 26) } # the quarters ending in March and June are due

    def declare(quarter_start, status)
      create(:vat_declaration, fiscal_year: fiscal_year, period_type: :quarterly, period_start: quarter_start,
             period_end: quarter_start.next_month.next_month.end_of_month, status: status)
    end

    it "counts the periods already over whose declaration was not submitted" do
      entity.update!(vat_filing_frequency: :quarterly)
      declare(Date.new(fiscal_year.year, 1, 1), :submitted)
      declare(Date.new(fiscal_year.year, 4, 1), :draft)

      expect(check(:vat_declarations, checklist(as_of: today))).to have_attributes(status: :warning, count: 1)
    end

    it "is clear when every past period has been submitted or accepted" do
      declare(Date.new(fiscal_year.year, 1, 1), :accepted)
      declare(Date.new(fiscal_year.year, 4, 1), :submitted)
      expect(check(:vat_declarations, checklist(as_of: today))).to have_attributes(status: :ok)
    end

    it "expects one declaration a month for a monthly filer" do
      entity.update!(vat_filing_frequency: :monthly)
      create(:vat_declaration, fiscal_year: fiscal_year, period_type: :monthly, period_start: Date.new(fiscal_year.year, 1, 1),
             period_end: Date.new(fiscal_year.year, 1, 31), status: :submitted)

      expect(check(:vat_declarations, checklist(as_of: today))).to have_attributes(status: :warning, count: 7) # Feb to Aug
    end

    it "has no fixed asset VAT review to do for a taxpayer who deducts VAT in full" do
      expect(check(:vat_review)).to be_nil
    end

    it "does not exist under the franchise: nothing is declared" do
      entity.update!(vat_regime: :franchise)
      expect(check(:vat_declarations)).to be_nil
      expect(check(:vat_review)).to be_nil
    end

    it "counts the fixed assets whose VAT is still under review, for a mixed taxpayer" do
      entity.update!(vat_scheme: :mixed)
      allow_any_instance_of(Accounting::FixedAsset).to receive(:under_review?).and_return(true)
      create(:fixed_asset)
      expect(check(:vat_review)).to have_attributes(status: :warning, count: 1)
    end
  end

  describe "the next fiscal year" do
    before { entity.update!(vat_regime: :franchise) }

    it "is information, not a warning, when it does not exist yet" do
      expect(check(:next_fiscal_year)).to have_attributes(status: :info)
      expect(checklist.warnings_count).to eq(0)
    end

    it "is clear once it exists" do
      create(:fiscal_year, year: fiscal_year.year + 1, start_date: fiscal_year.end_date + 1, end_date: fiscal_year.end_date + 1.year, status: :closed)
      expect(check(:next_fiscal_year)).to have_attributes(status: :ok)
    end
  end
end
