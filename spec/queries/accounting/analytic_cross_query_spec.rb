require "rails_helper"

RSpec.describe Accounting::AnalyticCrossQuery, type: :query do
  include_context "with_open_fiscal_year"

  let!(:proj_axis)  { create(:analytical_axis, :proj) }
  let!(:act_axis)   { create(:analytical_axis, :act) }
  let!(:proj_alpha) { create(:analytical_account, analytical_axis: proj_axis, code: "PROJ-001", label_fr: "Alpha") }
  let!(:proj_beta)  { create(:analytical_account, analytical_axis: proj_axis, code: "PROJ-002", label_fr: "Beta") }
  let!(:act_conf)   { create(:analytical_account, analytical_axis: act_axis, code: "ACT-001", label_fr: "Conference") }
  let!(:act_train)  { create(:analytical_account, analytical_axis: act_axis, code: "ACT-002", label_fr: "Training") }

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

  def create_cross_entry(proj_account:, act_account:, amount:, debit_acct: expense_account, credit_acct: liability_account)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                   entry_date: fiscal_year.start_date + 10)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    line = create(:journal_entry_line, journal_entry: entry,
                  account: debit_acct, debit: amount, credit: BigDecimal("0"))
    create(:analytical_annotation, journal_entry_line: line,
           analytical_axis: proj_axis, analytical_account: proj_account)
    create(:analytical_annotation, journal_entry_line: line,
           analytical_axis: act_axis, analytical_account: act_account)
    create(:journal_entry_line, journal_entry: entry,
           account: credit_acct, debit: BigDecimal("0"), credit: amount)
    entry.post!
  end

  subject(:results) do
    described_class.new(fiscal_year: fiscal_year, row_axis: proj_axis, col_axis: act_axis).call
  end

  it "returns empty when no cross-annotated entries exist" do
    expect(results).to be_empty
  end

  context "with cross-annotated entries" do
    before do
      create_cross_entry(proj_account: proj_alpha, act_account: act_conf,  amount: BigDecimal("1000.00"))
      create_cross_entry(proj_account: proj_alpha, act_account: act_train, amount: BigDecimal("500.00"))
      create_cross_entry(proj_account: proj_beta,  act_account: act_conf,  amount: BigDecimal("300.00"))
    end

    it "returns one result per (row_account, col_account) combination" do
      expect(results.count).to eq(3)
    end

    it "aggregates charges per combination" do
      alpha_conf = results.find { |r| r.row_account.code == "PROJ-001" && r.col_account.code == "ACT-001" }
      expect(alpha_conf.charges).to eq(BigDecimal("1000.00"))
    end

    it "calculates solde as produits minus charges" do
      alpha_train = results.find { |r| r.row_account.code == "PROJ-001" && r.col_account.code == "ACT-002" }
      expect(alpha_train.solde).to eq(-BigDecimal("500.00"))
    end

    it "does not include lines annotated on only one axis" do
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                     entry_date: fiscal_year.start_date + 1)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      line = create(:journal_entry_line, journal_entry: entry,
                    account: expense_account, debit: BigDecimal("9999.00"), credit: BigDecimal("0"))
      create(:analytical_annotation, journal_entry_line: line,
             analytical_axis: proj_axis, analytical_account: proj_alpha)
      create(:journal_entry_line, journal_entry: entry,
             account: liability_account, debit: BigDecimal("0"), credit: BigDecimal("9999.00"))
      entry.post!

      expect(results.count).to eq(3)
    end

    it "aggregates multiple entries for the same combination" do
      create_cross_entry(proj_account: proj_alpha, act_account: act_conf, amount: BigDecimal("250.00"))

      alpha_conf = results.find { |r| r.row_account.code == "PROJ-001" && r.col_account.code == "ACT-001" }
      expect(alpha_conf.charges).to eq(BigDecimal("1250.00"))
    end

    it "includes produits from revenue accounts" do
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                     entry_date: fiscal_year.start_date + 3)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      line = create(:journal_entry_line, journal_entry: entry,
                    account: revenue_account, debit: BigDecimal("0"), credit: BigDecimal("600.00"))
      create(:analytical_annotation, journal_entry_line: line,
             analytical_axis: proj_axis, analytical_account: proj_beta)
      create(:analytical_annotation, journal_entry_line: line,
             analytical_axis: act_axis, analytical_account: act_train)
      create(:journal_entry_line, journal_entry: entry,
             account: liability_account, debit: BigDecimal("600.00"), credit: BigDecimal("0"))
      entry.post!

      beta_train = results.find { |r| r.row_account.code == "PROJ-002" && r.col_account.code == "ACT-002" }
      expect(beta_train.produits).to eq(BigDecimal("600.00"))
    end
  end
end
