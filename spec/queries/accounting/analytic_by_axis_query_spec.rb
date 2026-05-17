require "rails_helper"

RSpec.describe Accounting::AnalyticByAxisQuery, type: :query do
  include_context "with_open_fiscal_year"

  let!(:axis)       { create(:analytical_axis, :proj) }
  let!(:proj_alpha) { create(:analytical_account, analytical_axis: axis, code: "PROJ-001", label_fr: "Alpha") }
  let!(:proj_beta)  { create(:analytical_account, analytical_axis: axis, code: "PROJ-002", label_fr: "Beta") }
  let!(:other_axis) { create(:analytical_axis, :act) }
  let!(:other_acct) { create(:analytical_account, analytical_axis: other_axis, code: "ACT-001", label_fr: "Conf") }

  let(:journal) { create(:journal, :purchase) }
  let!(:expense_account) do
    create(:account, code: "604000", label_fr: "Services",
           account_type: :expense, normal_balance: :debit, account_class: 6)
  end
  let!(:revenue_account) do
    create(:account, code: "700000", label_fr: "Ventes",
           account_type: :revenue, normal_balance: :credit, account_class: 7)
  end
  let!(:liability_account) do
    create(:account, code: "440000", label_fr: "Fournisseurs",
           account_type: :liability, normal_balance: :credit, account_class: 4)
  end

  def create_annotated_entry(analytical_account:, amount:, debit_account: expense_account, credit_account: liability_account)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                   entry_date: fiscal_year.start_date + 10)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    line = create(:journal_entry_line, journal_entry: entry,
                  account: debit_account, debit: amount, credit: BigDecimal("0"))
    create(:analytical_annotation, journal_entry_line: line,
           analytical_axis: axis, analytical_account: analytical_account)
    create(:journal_entry_line, journal_entry: entry,
           account: credit_account, debit: BigDecimal("0"), credit: amount)
    entry.post!
  end

  subject(:results) { described_class.new(fiscal_year: fiscal_year, axis: axis).call }

  it "returns an empty array when no annotated entries exist" do
    expect(results).to be_empty
  end

  it "excludes draft entries" do
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                   entry_date: fiscal_year.start_date + 1)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    line = create(:journal_entry_line, journal_entry: entry,
                  account: expense_account, debit: BigDecimal("500.00"), credit: BigDecimal("0"))
    create(:analytical_annotation, journal_entry_line: line,
           analytical_axis: axis, analytical_account: proj_alpha)
    create(:journal_entry_line, journal_entry: entry,
           account: liability_account, debit: BigDecimal("0"), credit: BigDecimal("500.00"))

    expect(results).to be_empty
  end

  context "with annotated posted entries" do
    before do
      create_annotated_entry(analytical_account: proj_alpha, amount: BigDecimal("500.00"))
      create_annotated_entry(analytical_account: proj_alpha, amount: BigDecimal("300.00"))
      create_annotated_entry(analytical_account: proj_beta,  amount: BigDecimal("200.00"))
    end

    it "returns one result per analytical account with movements" do
      expect(results.count).to eq(2)
    end

    it "aggregates charges per analytical account" do
      alpha = results.find { |r| r.analytical_account.code == "PROJ-001" }
      expect(alpha.charges).to eq(BigDecimal("800.00"))
    end

    it "calculates solde as produits minus charges" do
      beta = results.find { |r| r.analytical_account.code == "PROJ-002" }
      expect(beta.solde).to eq(-BigDecimal("200.00"))
    end

    it "orders results by analytical account code" do
      codes = results.map { |r| r.analytical_account.code }
      expect(codes).to eq(codes.sort)
    end

    it "does not include lines annotated only on a different axis" do
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                     entry_date: fiscal_year.start_date + 1)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      line = create(:journal_entry_line, journal_entry: entry,
                    account: expense_account, debit: BigDecimal("9999.00"), credit: BigDecimal("0"))
      create(:analytical_annotation, journal_entry_line: line,
             analytical_axis: other_axis, analytical_account: other_acct)
      create(:journal_entry_line, journal_entry: entry,
             account: liability_account, debit: BigDecimal("0"), credit: BigDecimal("9999.00"))
      entry.post!

      expect(results.count).to eq(2)
    end

    it "includes produits from revenue accounts" do
      # Credit on revenue account → produits
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                     entry_date: fiscal_year.start_date + 5)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      line = create(:journal_entry_line, journal_entry: entry,
                    account: revenue_account, debit: BigDecimal("0"), credit: BigDecimal("400.00"))
      create(:analytical_annotation, journal_entry_line: line,
             analytical_axis: axis, analytical_account: proj_alpha)
      create(:journal_entry_line, journal_entry: entry,
             account: liability_account, debit: BigDecimal("400.00"), credit: BigDecimal("0"))
      entry.post!

      alpha = results.find { |r| r.analytical_account.code == "PROJ-001" }
      expect(alpha.produits).to eq(BigDecimal("400.00"))
      expect(alpha.solde).to eq(-BigDecimal("400.00")) # 400 produits - 800 charges
    end
  end
end
