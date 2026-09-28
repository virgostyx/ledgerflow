require "rails_helper"

# R03 — vue centralisatrice (docs/dev/reports/spec.md §6): par journal et par
# mois, nombre d'écritures, total débit/crédit.
RSpec.describe Accounting::JournalSummaryQuery, type: :query do
  include_context "with_open_fiscal_year"

  let(:journal)       { create(:journal, :purchase) }
  let(:other_journal) { create(:journal, :sale) }
  let!(:expense_account)   { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:liability_account) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  def post(journal:, entry_date:, amount:)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: entry_date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense_account, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: liability_account, debit: 0, credit: amount)
    entry.post!
  end

  subject(:rows) { described_class.new(fiscal_year: fiscal_year).call }

  it "groups by journal and calendar month, counting entries and summing debit/credit" do
    post(journal: journal, entry_date: fiscal_year.start_date + 1, amount: BigDecimal("100"))
    post(journal: journal, entry_date: fiscal_year.start_date + 2, amount: BigDecimal("50"))
    post(journal: other_journal, entry_date: fiscal_year.start_date + 40, amount: BigDecimal("30"))

    row = rows.find { |r| r.journal_id == journal.id }
    expect(row.entry_count).to eq(2)
    expect(row.total_debit).to eq(BigDecimal("150"))
    expect(row.total_credit).to eq(BigDecimal("150"))
    expect(rows.map(&:journal_id)).to include(other_journal.id)
  end

  it "keeps debit == credit per journal (I1, restated per journal)" do
    post(journal: journal, entry_date: fiscal_year.start_date + 1, amount: BigDecimal("75"))

    rows.each { |row| expect(row.total_debit).to eq(row.total_credit) }
  end

  it "excludes draft entries" do
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 1)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense_account, debit: 999, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: liability_account, debit: 0, credit: 999)

    expect(rows).to be_empty
  end
end
