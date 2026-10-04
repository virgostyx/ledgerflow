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

  describe "an account kept in a foreign currency (F11)" do
    let!(:usd_account) { create(:account, code: "467001", label_fr: "Held in USD", account_type: :asset, normal_balance: :debit, account_class: 4, currency: "USD") }

    def post_usd(amount_usd:, eur:, side:)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 40)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      sign = side == :debit ? 1 : -1
      create(:journal_entry_line, journal_entry: entry, account: usd_account, side => BigDecimal(eur), (side == :debit ? :credit : :debit) => 0,
             currency: "USD", amount_currency: sign * BigDecimal(amount_usd), exchange_rate: (BigDecimal(amount_usd) / BigDecimal(eur)).round(8))
      create(:journal_entry_line, journal_entry: entry, account: liability_account, (side == :debit ? :credit : :debit) => BigDecimal(eur), side => 0)
      entry.post!
    end

    it "carries its currency and its balance in that currency, net of what went out" do
      post_usd(amount_usd: "1100", eur: "1000", side: :debit)
      post_usd(amount_usd: "330", eur: "300", side: :credit)

      row = described_class.new(fiscal_year: fiscal_year).call.find { |r| r.code == "467001" }
      expect(row).to have_attributes(currency: "USD", balance_in_currency: BigDecimal("770"), balance: BigDecimal("700"))
    end

    it "has neither for an account kept in EUR" do
      row = described_class.new(fiscal_year: fiscal_year).call.find { |r| r.code == "604000" }
      expect(row).to have_attributes(currency: nil, balance_in_currency: nil)
    end
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

  # docs/dev/reports/spec.md §5: ouverture (avant date_from), mouvements (bruts,
  # entre date_from et as_of), clôture = ouverture + mouvements.
  describe "opening/movement breakdown (date_from)" do
    subject(:row) do
      described_class.new(fiscal_year: fiscal_year, date_from: fiscal_year.start_date + 15, as_of: fiscal_year.start_date + 25)
        .call.find { |r| r.code == "604000" }
    end

    it "sums lines before date_from into the opening balance" do
      expect(row.opening_debit).to eq(BigDecimal("1000.00"))
      expect(row.opening_credit).to eq(0)
    end

    it "sums lines from date_from to as_of into gross movements" do
      expect(row.movement_debit).to eq(BigDecimal("500.00"))
      expect(row.movement_credit).to eq(0)
    end

    it "keeps total_debit/total_credit as the full cumulative closing figures (opening + movement)" do
      expect(row.total_debit).to eq(BigDecimal("1500.00"))
    end

    it "defaults date_from to the fiscal year's start, so opening is zero without it" do
      full_row = described_class.new(fiscal_year: fiscal_year, as_of: fiscal_year.start_date + 25)
        .call.find { |r| r.code == "604000" }
      expect(full_row.opening_debit).to eq(0)
      expect(full_row.movement_debit).to eq(BigDecimal("1500.00"))
    end
  end

  describe "excluding the closing entry" do
    let!(:revenue_account) do
      create(:account, code: "700000", label_fr: "Ventes", account_type: :revenue, normal_balance: :credit, account_class: 7)
    end
    let!(:result_account) do
      create(:account, code: "699000", label_fr: "Résultat", account_type: :expense, normal_balance: :debit, account_class: 6)
    end

    before do
      create_posted_entry(entry_date: fiscal_year.start_date + 20, debit_account: liability_account,
                          credit_account: revenue_account, amount: BigDecimal("500"))
      closing = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.end_date,
                       source_type: Accounting::JournalEntry::CLOSING_SOURCE)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: closing, account: revenue_account, debit: 500, credit: 0)
      create(:journal_entry_line, journal_entry: closing, account: result_account, debit: 0, credit: 500)
      closing.post!
    end

    it "shows the closing entry by default: the revenue accounts are settled" do
      row = described_class.new(fiscal_year: fiscal_year).call.find { |r| r.code == "700000" }
      expect(row.balance).to eq(0)
    end

    it "leaves it out on request, so that the income of a closed year can still be read" do
      rows = described_class.new(fiscal_year: fiscal_year, exclude_closing: true).call
      expect(rows.find { |r| r.code == "700000" }.balance).to eq(500)
      expect(rows.map(&:code)).not_to include("699000")
    end
  end

  describe "isolation" do
    let(:rows_from_other_entity) do
      other_fiscal_year = ActsAsTenant.with_tenant(create(:entity)) { create(:fiscal_year) }
      described_class.new(fiscal_year: other_fiscal_year).call
    end

    it_behaves_like "entity scoped report"
  end
end
