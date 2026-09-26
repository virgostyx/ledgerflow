require "rails_helper"

RSpec.describe Accounting::AnnualAccounts, type: :query do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let(:user)    { create(:user, role: :accountant) }

  def account(code, type, normal, label = "Account #{code}")
    create(:account, code: code, label_fr: label, account_type: type, normal_balance: normal, account_class: code[0].to_i)
  end

  let!(:capital)   { account("101000", :equity, :credit) }
  let!(:building)  { account("220000", :asset, :debit) }
  let!(:customers) { account("400000", :asset, :debit) }
  let!(:suppliers) { account("440000", :liability, :credit) }
  let!(:bank)      { account("550000", :asset, :debit) }
  let!(:carry)     { account("130000", :equity, :credit) }
  let!(:goods)     { account("600100", :expense, :debit) }
  let!(:bank_fees) { account("651100", :expense, :debit) }
  let!(:sales)     { account("700000", :revenue, :credit) }
  let!(:interest)  { account("750000", :revenue, :credit) }

  def post(debit, credit, amount, on: fiscal_year.start_date + 10, year: fiscal_year)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: year, entry_date: on)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: debit,  debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: credit, debit: 0, credit: amount)
    entry.post!
  end

  # Contribution 10000, building 5000, sale 3000 (on credit), purchases 1000 (on credit), bank fees 50, interest 20.
  before do
    post(bank, capital, 10_000)
    post(building, bank, 5_000)
    post(customers, sales, 3_000)
    post(goods, suppliers, 1_000)
    post(bank_fees, bank, 50)
    post(bank, interest, 20)
  end

  let(:report) { described_class.new(fiscal_year: fiscal_year).call }

  def amount(statement, code) = report.rows(statement).find { |r| r.code == code }.amount

  describe "the balance sheet" do
    it "groups the assets by legal heading, with their sub-totals" do
      expect(amount(:assets, "22/27")).to eq(5_000)
      expect(amount(:assets, "40/41")).to eq(3_000)
      expect(amount(:assets, "54/58")).to eq(4_970)
      expect(amount(:assets, "20/28")).to eq(5_000)
      expect(amount(:assets, "29/58")).to eq(7_970)
      expect(amount(:assets, "20/58")).to eq(12_970)
    end

    it "groups the equity and debts, and puts the result of the year in the profit carried forward" do
      expect(amount(:liabilities, "10/11")).to eq(10_000)
      expect(amount(:liabilities, "14")).to eq(1_970)
      expect(amount(:liabilities, "10/15")).to eq(11_970)
      expect(amount(:liabilities, "42/48")).to eq(1_000)
      expect(amount(:liabilities, "10/49")).to eq(12_970)
    end

    it "adds the carry-forward account 130000 to the profit carried forward, not to the reserves" do
      post(bank, carry, 400)
      expect(amount(:liabilities, "13")).to eq(0)
      expect(amount(:liabilities, "14")).to eq(2_370)
    end

    it "is balanced" do
      expect(report).to be_balanced
      expect(report.difference).to eq(0)
    end
  end

  describe "the income statement" do
    it "gives the operating income and charges, and each level of result" do
      expect(amount(:income, "70")).to eq(3_000)
      expect(amount(:income, "70/76A")).to eq(3_000)
      expect(amount(:income, "60")).to eq(1_000)
      expect(amount(:income, "60/66A")).to eq(1_000)
      expect(amount(:income, "9901")).to eq(2_000)
      expect(amount(:income, "75/76B")).to eq(20)
      expect(amount(:income, "65/66B")).to eq(50)
      expect(amount(:income, "9902")).to eq(1_970)
      expect(amount(:income, "9903")).to eq(1_970)
      expect(amount(:income, "9904")).to eq(1_970)
    end

    it "takes income taxes off the result" do
      post(account("670000", :expense, :debit), suppliers, 300)
      expect(amount(:income, "67/77")).to eq(300)
      expect(amount(:income, "9904")).to eq(1_670)
      expect(amount(:liabilities, "14")).to eq(1_670)
    end

    it "counts a loss as a negative result" do
      post(goods, suppliers, 5_000)
      expect(amount(:income, "9904")).to eq(-3_030)
    end
  end

  describe "a closed fiscal year" do
    let!(:closing_journal) { create(:journal, code: "CLO", label_fr: "Clôture", journal_type: :misc, sequence_prefix: "CLO") }
    let!(:result_account)  { account("699000", :expense, :debit, "Résultat de l'exercice") }

    it "gives the same figures as before its closing entry" do
      before = report.rows(:income).to_h { |r| [ r.code, r.amount ] }
      expect(Accounting::CloseFiscalYear.call(fiscal_year: fiscal_year, closed_by: user)).to be_success

      closed = described_class.new(fiscal_year: fiscal_year.reload).call
      expect(closed.rows(:income).to_h { |r| [ r.code, r.amount ] }).to eq(before)
      expect(closed.rows(:liabilities).find { |r| r.code == "14" }.amount).to eq(1_970)
      expect(closed).to be_balanced
    end
  end

  describe "the previous fiscal year" do
    let!(:previous_year) do
      create(:fiscal_year, year: fiscal_year.year - 1, start_date: fiscal_year.start_date - 1.year,
             end_date: fiscal_year.start_date - 1.day, status: :closed)
    end

    before do
      post(customers, sales, 800, on: previous_year.start_date + 5, year: previous_year)
      post(bank, capital, 700, on: previous_year.start_date + 6, year: previous_year)
    end

    it "is shown next to the current one" do
      row = report.rows(:income).find { |r| r.code == "70" }
      expect(row).to have_attributes(amount: 3_000, previous: 800)
      expect(report.rows(:liabilities).find { |r| r.code == "10/11" }.previous).to eq(700)
      expect(report.previous_year).to eq(previous_year)
    end
  end

  it "has no previous figures without a previous fiscal year" do
    expect(report.previous_year).to be_nil
    expect(report.rows(:income).first.previous).to be_nil
  end

  describe "the accounts that fit no heading" do
    it "lists the ones with a balance, so that nothing is silently left out" do
      other = account("590000", :asset, :debit, "Internal transfers")
      post(other, bank, 70)

      expect(report.unmapped.map(&:code)).to eq([ "590000" ])
      expect(report.unmapped.first.balance).to eq(70)
      expect(report).not_to be_balanced
    end

    it "ignores the appropriations of the result (69, 79)" do
      post(account("693000", :expense, :debit, "Profit to carry forward"), suppliers, 10)
      expect(report.unmapped).to be_empty
    end

    it "ignores the result account and accounts without a balance" do
      account("699000", :expense, :debit)
      expect(report.unmapped).to be_empty
    end
  end
end
