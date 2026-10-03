require "rails_helper"

# I5 and F02 criterion 8: after the import of a CODA statement, and whatever has been matched, the R06 gap is zero.
RSpec.describe "Invariant I5 — the gap of R06 after a CODA import", type: :invariant do
  include_context "with_open_fiscal_year"

  let!(:bank_gl) { create(:account, code: "550000", label_fr: "Banque", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:equity_account) { create(:account, code: "100000", label_fr: "Capital", account_type: :equity, normal_balance: :credit) }
  let!(:expense) { create(:account, code: "613000", label_fr: "Charges") }
  let!(:bank_journal) { create(:journal, :bank, default_account: bank_gl) }
  let(:acme) { CodaBuilder.iban("539007547034") }
  let!(:bank_account) { create(:bank_account, iban: acme, journal: bank_journal) }
  let(:user) { create(:user) }

  # The bank opened the account with 1 000,00: the ledger opening entry says the same.
  before do
    entry = create(:journal_entry, :draft, journal: create(:journal, :misc), fiscal_year: fiscal_year, entry_date: Date.new(2026, 3, 1))
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: bank_gl, debit: 1000, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: equity_account, debit: 0, credit: 1000)
    entry.post!
    Banking::ImportStatements.call(bytes: File.binread(Rails.root.join("spec/fixtures/files/coda/simple.cod")), user: user, source_name: "simple.cod")
  end

  def gap = Accounting::BankReconciliationQuery.new(bank_account: bank_account, as_of: Date.new(2026, 3, 31)).call.gap

  it "is zero as soon as the file is imported, the lines being on the statement and not yet booked" do
    expect(gap).to eq(0)
  end

  it "stays zero as the lines are booked, one by one" do
    Accounting::BankTransaction.order(:id).each do |transaction|
      result = Accounting::ReconcileBankTransaction.call(transaction: transaction, account_id: expense.id, fiscal_year: fiscal_year, label: "x")
      expect(result).to be_success
      expect(gap).to eq(0)
    end
  end

  it "stays zero when a booking is undone" do
    transaction = Accounting::BankTransaction.order(:id).first
    Accounting::ReconcileBankTransaction.call(transaction: transaction, account_id: expense.id, fiscal_year: fiscal_year, label: "x", draft: true)
    Banking::UndoMatch.call(transaction: transaction.reload, user: user)

    expect(gap).to eq(0)
  end
end
