require "rails_helper"

RSpec.describe Accounting::GeneralLedgerQuery, type: :query do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:account) do
    create(:account, code: "604000", label_fr: "Services",
           account_type: :expense, normal_balance: :debit, account_class: 6)
  end
  let!(:other_account) do
    create(:account, code: "440000", label_fr: "Fournisseurs",
           account_type: :liability, normal_balance: :credit, account_class: 4)
  end

  def create_posted_entry(entry_date:, amount:, label: "Ligne")
    entry = create(:journal_entry, :draft, journal: journal,
                   fiscal_year: fiscal_year, entry_date: entry_date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account,
           debit: amount, credit: BigDecimal("0"), label: label)
    create(:journal_entry_line, journal_entry: entry, account: other_account,
           debit: BigDecimal("0"), credit: amount)
    entry.post!
    entry
  end

  before do
    create_posted_entry(entry_date: fiscal_year.start_date + 5,
                        amount: BigDecimal("500.00"), label: "Première écriture")
    create_posted_entry(entry_date: fiscal_year.start_date + 15,
                        amount: BigDecimal("300.00"), label: "Deuxième écriture")
    create_posted_entry(entry_date: fiscal_year.start_date + 25,
                        amount: BigDecimal("200.00"), label: "Troisième écriture")
  end

  describe "#call" do
    subject(:results) do
      described_class.new(account: account, fiscal_year: fiscal_year).call
    end

    it "retourne un tableau de résultats" do
      expect(results).to be_an(Array)
    end

    it "retourne uniquement les lignes du compte demandé" do
      expect(results.count).to eq(3)
    end

    it "inclut le label de chaque ligne" do
      labels = results.map(&:label)
      expect(labels).to include("Première écriture", "Deuxième écriture", "Troisième écriture")
    end

    it "trie par date croissante" do
      dates = results.map(&:entry_date)
      expect(dates).to eq(dates.sort)
    end

    it "calcule le solde cumulatif croissant" do
      expect(results[0].running_balance).to eq(BigDecimal("500.00"))
      expect(results[1].running_balance).to eq(BigDecimal("800.00"))
      expect(results[2].running_balance).to eq(BigDecimal("1000.00"))
    end

    context "avec filtre de dates" do
      it "retourne uniquement les lignes dans la période" do
        date_from = fiscal_year.start_date + 10
        date_to   = fiscal_year.start_date + 20
        results = described_class.new(account: account, fiscal_year: fiscal_year,
                                      date_from: date_from, date_to: date_to).call
        expect(results.count).to eq(1)
        expect(results.first.label).to eq("Deuxième écriture")
      end
    end

    context "avec un autre compte" do
      it "ne retourne pas les lignes d'un autre compte" do
        results = described_class.new(account: other_account, fiscal_year: fiscal_year).call
        expect(results.count).to eq(3)
        results.each { |r| expect(r.debit).to eq(BigDecimal("0")) }
      end
    end

    context "écritures brouillon exclues" do
      it "n'inclut pas les écritures non validées" do
        draft = create(:journal_entry, :draft, journal: journal,
                       fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 1)
        ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
        create(:journal_entry_line, journal_entry: draft, account: account,
               debit: BigDecimal("9999.00"), credit: BigDecimal("0"))
        results = described_class.new(account: account, fiscal_year: fiscal_year).call
        expect(results.sum(&:debit)).to eq(BigDecimal("1000.00"))
      end
    end
  end
end
