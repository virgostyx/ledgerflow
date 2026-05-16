require "rails_helper"

RSpec.describe Accounting::AnalyticProjectQuery, type: :query do
  include_context "with_open_fiscal_year"

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

  def create_posted_entry(project_id:, debit_account:, credit_account:, amount:)
    entry = create(:journal_entry, :draft, journal: journal,
                   fiscal_year: fiscal_year,
                   entry_date: fiscal_year.start_date + 10,
                   project_id: project_id)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry,
           account: debit_account, debit: amount, credit: BigDecimal("0"))
    create(:journal_entry_line, journal_entry: entry,
           account: credit_account, debit: BigDecimal("0"), credit: amount)
    entry.post!
    entry
  end

  before do
    create_posted_entry(project_id: 1, debit_account: expense_account,
                        credit_account: liability_account, amount: BigDecimal("800.00"))
    create_posted_entry(project_id: 1, debit_account: expense_account,
                        credit_account: liability_account, amount: BigDecimal("200.00"))
    create_posted_entry(project_id: 2, debit_account: expense_account,
                        credit_account: liability_account, amount: BigDecimal("500.00"))
  end

  describe "#call — tous les projets" do
    subject(:results) { described_class.new(fiscal_year: fiscal_year).call }

    it "retourne un tableau de résultats" do
      expect(results).to be_an(Array)
    end

    it "retourne un résultat par projet ayant des mouvements" do
      expect(results.count).to be >= 2
    end

    it "agrège les charges par projet" do
      proj1 = results.find { |r| r.project_id == 1 }
      expect(proj1.charges).to eq(BigDecimal("1000.00"))
    end

    it "calcule le solde (produits - charges)" do
      proj2 = results.find { |r| r.project_id == 2 }
      expect(proj2.solde).to eq(-BigDecimal("500.00"))
    end
  end

  describe "#call — filtré par project_id" do
    subject(:results) { described_class.new(fiscal_year: fiscal_year, project_id: 1).call }

    it "retourne uniquement le projet demandé" do
      project_ids = results.map(&:project_id)
      expect(project_ids).to eq([1])
    end

    it "agrège toutes les charges du projet 1" do
      expect(results.first.charges).to eq(BigDecimal("1000.00"))
    end
  end

  describe "#call — avec produits" do
    before do
      create_posted_entry(project_id: 1, debit_account: liability_account,
                          credit_account: revenue_account, amount: BigDecimal("1500.00"))
    end

    it "agrège les produits (crédit comptes de produits)" do
      results = described_class.new(fiscal_year: fiscal_year, project_id: 1).call
      expect(results.first.produits).to eq(BigDecimal("1500.00"))
    end

    it "calcule le solde positif quand produits > charges" do
      results = described_class.new(fiscal_year: fiscal_year, project_id: 1).call
      expect(results.first.solde).to eq(BigDecimal("500.00"))
    end
  end
end
