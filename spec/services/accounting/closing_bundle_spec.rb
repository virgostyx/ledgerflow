require "rails_helper"
require "csv"

RSpec.describe "R20 closing bundle, audit export and filing data", type: :service do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:bank)   { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:sales)  { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:costs)  { create(:account, code: "600000", label_fr: "Purchases", account_class: 6, account_type: :expense, normal_balance: :debit) }

  def post(*lines)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    lines.each { |account, debit, credit| create(:journal_entry_line, journal_entry: entry, account: account, debit: debit, credit: credit) }
    entry.post!
    entry
  end

  before do
    post([ bank, 1234.56, 0 ], [ sales, 0, 1234.56 ])
    post([ costs, 200, 0 ], [ bank, 0, 200 ])
    create(:vat_declaration, fiscal_year: fiscal_year, period_start: fiscal_year.start_date, period_end: fiscal_year.start_date + 89, grids: { "03" => "1000.00", "54" => "210.00" })
  end

  describe Accounting::ClosingBundle do
    let(:result) { described_class.call(fiscal_year: fiscal_year) }
    let(:contents) { Accounting::Zipper.read(result.zip) }

    it "contains the PDFs of R01, R02, R04, R07, R08, R09, R16, R17, the filing data and a manifest" do
      expect(contents.keys).to include("R01_trial_balance.pdf", "R02_general_ledger.pdf", "R04_aged_balance_customers.pdf", "R04_aged_balance_suppliers.pdf",
                                       "R07_balance_sheet.pdf", "R08_income_statement.pdf", "R09_vat_declarations.pdf", "R16_fixed_assets.pdf",
                                       "R17_regularizations.pdf", "filing_data.json", "manifest.json")
      contents.select { |name, _| name.end_with?(".pdf") }.each_value { |pdf| expect(pdf).to start_with("%PDF") }
    end

    it "lists every file with its SHA-256 and the generation date, and verifies" do
      manifest = JSON.parse(contents.fetch("manifest.json"))
      expect(manifest["generated_at"]).to be_present
      expect(manifest["files"].map { |f| f["path"] }).to match_array(contents.keys - [ "manifest.json" ])
      manifest["files"].each { |f| expect(f["sha256"]).to eq(Digest::SHA256.hexdigest(contents.fetch(f["path"]))) }
      verification = described_class.verify(result.zip)
      expect(verification).to be_valid
      expect(verification.checked).to eq(manifest["files"].size)
    end

    it "detects a file altered after generation, and a file removed" do
      altered = contents.merge("R01_trial_balance.pdf" => "tampered")
      expect(described_class.verify(Accounting::Zipper.build(altered.to_a)).mismatches).to eq([ "R01_trial_balance.pdf" ])
      trimmed = contents.except("R08_income_statement.pdf")
      expect(described_class.verify(Accounting::Zipper.build(trimmed.to_a)).missing).to eq([ "R08_income_statement.pdf" ])
    end

    it "regenerates identically from the same data (only the manifest date may differ)" do
      first = contents
      second = Accounting::Zipper.read(described_class.call(fiscal_year: fiscal_year).zip)
      expect(second.except("manifest.json")).to eq(first.except("manifest.json"))
      expect(JSON.parse(second["manifest.json"])["files"]).to eq(JSON.parse(first["manifest.json"])["files"])
    end

    it "carries the same totals as the screens: the trial balance PDF shows the query's figures" do
      text = PDF::Reader.new(StringIO.new(contents.fetch("R01_trial_balance.pdf"))).pages.map(&:text).join
      expect(text).to include("1234.56", "200.00", "700000", "Sales")
      vat_text = PDF::Reader.new(StringIO.new(contents.fetch("R09_vat_declarations.pdf"))).pages.map(&:text).join
      expect(vat_text).to include("210.00", "1000.00")
    end

    it "includes the frozen bank reconciliations of the year" do
      bank_account = create(:bank_account)
      Accounting::BankReconciliationReport.record!(bank_account: bank_account, as_of: fiscal_year.start_date + 20, result: { gap: "0.0" })
      names = Accounting::Zipper.read(described_class.call(fiscal_year: fiscal_year).zip).keys
      expect(names.grep(/\AR06_bank_reconciliations\//).size).to eq(1)
    end
  end

  describe Accounting::AuditExport do
    let(:contents) { Accounting::Zipper.read(described_class.call(fiscal_year: fiscal_year)) }

    it "exports every entry line flat, in CSV and JSON, balanced" do
      rows = CSV.parse(contents.fetch("entries.csv"), headers: true)
      json = JSON.parse(contents.fetch("entries.json"))
      expect(rows.size).to eq(4)
      expect(json.size).to eq(4)
      expect(rows.sum { |r| BigDecimal(r["debit"]) }).to eq(rows.sum { |r| BigDecimal(r["credit"]) })
      expect(rows.map { |r| r["account"] }).to include("550000", "700000", "600000")
      expect(rows.map { |r| r["status"] }.uniq).to eq([ "posted" ])
      expect(json.first.keys).to eq(described_class::DATASETS["entries"][:headers])
    end

    it "exports the chart of accounts, partners, journals and VAT codes" do
      expect(contents.keys).to match_array(%w[entries accounts partners journals vat_codes].flat_map { |n| [ "#{n}.csv", "#{n}.json" ] })
      expect(CSV.parse(contents.fetch("accounts.csv"), headers: true).map { |r| r["code"] }).to include("550000")
      expect(CSV.parse(contents.fetch("vat_codes.csv"), headers: true).size).to be > 0
    end

    it "leaves out the entries of another fiscal year" do
      other = create(:fiscal_year, year: fiscal_year.year - 1, start_date: fiscal_year.start_date - 365, end_date: fiscal_year.start_date - 1, status: :closed)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: other, entry_date: other.start_date + 5)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: bank, debit: 1, credit: 0)
      expect(CSV.parse(contents.fetch("entries.csv"), headers: true).size).to eq(4)
    end
  end

  describe Accounting::FilingData do
    it "gives the rubric figures and the VAT grids as plain data" do
      data = described_class.call(fiscal_year: fiscal_year)
      expect(data[:fiscal_year]).to include(year: fiscal_year.year)
      expect(data[:income_statement].find { |r| r[:code] == "70" }[:amount]).to eq("1234.56")
      expect(data[:vat_declarations].sole[:grids]).to eq("03" => "1000.0", "54" => "210.0")
      expect(data[:balance_sheet].keys).to eq(%i[assets liabilities])
    end
  end
end
