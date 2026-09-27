require "rails_helper"

# docs/dev/reports/spec.md §6: chaque compte forme une section avec un solde
# d'ouverture ("Report") avant les mouvements de la période.
RSpec.describe Accounting::GeneralLedgerQuery, type: :query, bullet_strict: true do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let!(:account) do
    create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6)
  end
  let!(:other_account) do
    create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4)
  end

  def create_posted_entry(entry_date:, amount:, partner: nil, journal: self.journal)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: entry_date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    line = create(:journal_entry_line, journal_entry: entry, account: account, partner: partner,
                  debit: amount, credit: BigDecimal("0"))
    create(:journal_entry_line, journal_entry: entry, account: other_account, debit: BigDecimal("0"), credit: amount)
    entry.post!
    line
  end

  describe "opening_balance" do
    before do
      create_posted_entry(entry_date: fiscal_year.start_date + 5, amount: BigDecimal("500"))
      create_posted_entry(entry_date: fiscal_year.start_date + 15, amount: BigDecimal("300"))
    end

    it "sums lines before date_from, signed like the account's normal balance" do
      query = described_class.new(account: account, fiscal_year: fiscal_year, date_from: fiscal_year.start_date + 10)
      query.call
      expect(query.opening_balance).to eq(BigDecimal("500"))
    end

    it "is zero without a narrower date_from (nothing precedes the fiscal year's start)" do
      query = described_class.new(account: account, fiscal_year: fiscal_year)
      query.call
      expect(query.opening_balance).to eq(0)
    end

    it "carries into running_balance, so the section's closing balance is opening + movements" do
      query = described_class.new(account: account, fiscal_year: fiscal_year, date_from: fiscal_year.start_date + 10)
      rows = query.call
      expect(rows.last.running_balance).to eq(BigDecimal("800")) # 500 opening + 300 movement
    end
  end

  describe "filters" do
    let(:alice) { create(:partner, name: "Alice") }
    let(:bob)   { create(:partner, name: "Bob") }

    it "narrows to one partner (grand livre auxiliaire)" do
      create_posted_entry(entry_date: fiscal_year.start_date + 5, amount: BigDecimal("100"), partner: alice)
      create_posted_entry(entry_date: fiscal_year.start_date + 6, amount: BigDecimal("200"), partner: bob)

      rows = described_class.new(account: account, fiscal_year: fiscal_year, partner: alice).call
      expect(rows.map(&:debit)).to eq([ BigDecimal("100") ])
    end

    it "narrows to one journal" do
      other_journal = create(:journal, :purchase, code: "ACH2")
      create_posted_entry(entry_date: fiscal_year.start_date + 5, amount: BigDecimal("100"), journal: journal)
      create_posted_entry(entry_date: fiscal_year.start_date + 6, amount: BigDecimal("200"), journal: other_journal)

      rows = described_class.new(account: account, fiscal_year: fiscal_year, journal: other_journal).call
      expect(rows.map(&:debit)).to eq([ BigDecimal("200") ])
    end

    it "narrows to lettered or unlettered lines, and exposes the lettering code" do
      line = create_posted_entry(entry_date: fiscal_year.start_date + 5, amount: BigDecimal("100"))
      other = create_posted_entry(entry_date: fiscal_year.start_date + 6, amount: BigDecimal("200"))
      Accounting::JournalEntryLine.where(id: line.id).update_all(
        lettering_id: create(:lettering, account: account, entity: entity).id
      )

      lettered   = described_class.new(account: account, fiscal_year: fiscal_year, lettering: :lettered).call
      unlettered = described_class.new(account: account, fiscal_year: fiscal_year, lettering: :unlettered).call

      expect(lettered.map(&:debit)).to eq([ BigDecimal("100") ])
      expect(lettered.first.lettering_code).to be_present
      expect(unlettered.map(&:debit)).to eq([ BigDecimal("200") ])
      expect(unlettered.first.lettering_code).to be_nil
    end
  end
end
