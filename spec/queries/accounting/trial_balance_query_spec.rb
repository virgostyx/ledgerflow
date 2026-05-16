require "rails_helper"

RSpec.describe Accounting::TrialBalanceQuery, type: :query do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }

  let!(:expense_account) do
    create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6)
  end
  let!(:liability_account) do
    create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4)
  end

  def create_posted_entry(entry_date:, debit_account:, credit_account:, amount:)
    entry = create(:journal_entry, :draft, journal: journal,
                   fiscal_year: fiscal_year, entry_date: entry_date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: debit_account,
           debit: amount, credit: BigDecimal("0"))
    create(:journal_entry_line, journal_entry: entry, account: credit_account,
           debit: BigDecimal("0"), credit: amount)
    entry.post!
    entry
  end

  before do
    create_posted_entry(entry_date: fiscal_year.start_date + 10,
                        debit_account: expense_account,
                        credit_account: liability_account,
                        amount: BigDecimal("1000.00"))
    create_posted_entry(entry_date: fiscal_year.start_date + 20,
                        debit_account: expense_account,
                        credit_account: liability_account,
                        amount: BigDecimal("500.00"))
  end

  describe "#call" do
    subject(:results) { described_class.new(fiscal_year: fiscal_year).call }

    it "retourne un tableau de résultats" do
      expect(results).to be_an(Array)
    end

    it "inclut les comptes ayant des mouvements" do
      codes = results.map(&:code)
      expect(codes).to include("604000", "440000")
    end

    it "agrège les débits correctement" do
      expense = results.find { |r| r.code == "604000" }
      expect(expense.total_debit).to eq(BigDecimal("1500.00"))
    end

    it "agrège les crédits correctement" do
      liability = results.find { |r| r.code == "440000" }
      expect(liability.total_credit).to eq(BigDecimal("1500.00"))
    end

    it "calcule le solde correctement pour un compte débit normal" do
      expense = results.find { |r| r.code == "604000" }
      expect(expense.balance).to eq(BigDecimal("1500.00"))
    end

    it "calcule le solde correctement pour un compte crédit normal" do
      liability = results.find { |r| r.code == "440000" }
      expect(liability.balance).to eq(BigDecimal("1500.00"))
    end

    it "retourne les résultats triés par code" do
      codes = results.map(&:code)
      expect(codes).to eq(codes.sort)
    end

    it "exclut les comptes sans mouvement" do
      idle_account = create(:account, code: "999999", label_fr: "Sans mouvement",
                            account_class: 6)
      results_after = described_class.new(fiscal_year: fiscal_year).call
      expect(results_after.map(&:code)).not_to include("999999")
    end

    context "avec filtre as_of" do
      it "exclut les écritures postérieures à as_of" do
        as_of = fiscal_year.start_date + 15
        results = described_class.new(fiscal_year: fiscal_year, as_of: as_of).call
        expense = results.find { |r| r.code == "604000" }
        expect(expense.total_debit).to eq(BigDecimal("1000.00"))
      end
    end

    context "écritures brouillon exclues" do
      it "n'inclut pas les écritures non validées" do
        draft = create(:journal_entry, :draft, journal: journal,
                       fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 5)
        ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
        draft_account = create(:account, code: "888000", label_fr: "Brouillon",
                               account_class: 6)
        create(:journal_entry_line, journal_entry: draft, account: draft_account,
               debit: BigDecimal("999.00"), credit: BigDecimal("0"))

        results = described_class.new(fiscal_year: fiscal_year).call
        expect(results.map(&:code)).not_to include("888000")
      end
    end
  end
end
