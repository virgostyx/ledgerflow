require "rails_helper"

# F02: a line with no invoice behind it (an unknown line, a payment of several costs) is booked across several accounts.
RSpec.describe "Booking a bank line across several accounts" do
  include_context "with_open_fiscal_year"

  let!(:bank_gl)  { create(:account, code: "550000", label_fr: "Banque", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:rent)     { create(:account, code: "610000", label_fr: "Loyer") }
  let!(:charges)  { create(:account, code: "611000", label_fr: "Charges") }
  let!(:bank_journal) { create(:journal, :bank, default_account: bank_gl) }
  let(:bank_account) { create(:bank_account, journal: bank_journal) }
  let(:tx) { create(:bank_transaction, bank_account: bank_account, amount: -1000, description: "LOYER ET CHARGES") }

  def book(splits, **options) = Accounting::ReconcileBankTransaction.call(transaction: tx, account_id: nil, fiscal_year: fiscal_year, label: "Rent", splits: splits, **options)

  it "books one bank line and one line per account, the entry balancing" do
    expect(book([ [ rent.id, BigDecimal("850") ], [ charges.id, BigDecimal("150") ] ])).to be_success

    entry = tx.reload.journal_entry
    expect(tx).to be_reconciled
    expect(entry).to be_posted
    expect(entry.lines.find_by(account: bank_gl).credit).to eq(1000)
    expect(entry.lines.find_by(account: rent).debit).to eq(850)
    expect(entry.lines.find_by(account: charges).debit).to eq(150)
  end

  it "can be a draft, like any booking" do
    expect(book([ [ rent.id, BigDecimal("600") ], [ charges.id, BigDecimal("400") ] ], draft: true)).to be_success

    expect(tx.reload).to be_matched
    expect(tx.journal_entry).to be_draft
  end

  it "refuses amounts that do not add up to the movement, and books nothing" do
    result = book([ [ rent.id, BigDecimal("850") ], [ charges.id, BigDecimal("100") ] ])

    expect(result).to be_failure
    expect(result.message).to include("1000")
    expect(tx.reload).to be_pending
    expect(Accounting::JournalEntry.count).to eq(0)
  end

  it "works for a receipt too, the split being on the credit side" do
    income = create(:account, code: "700000", label_fr: "Ventes", account_type: :revenue, normal_balance: :credit, account_class: 7)
    other_income = create(:account, code: "740000", label_fr: "Subsides", account_type: :revenue, normal_balance: :credit, account_class: 7)
    receipt = create(:bank_transaction, bank_account: bank_account, amount: 300)

    Accounting::ReconcileBankTransaction.call(transaction: receipt, account_id: nil, fiscal_year: fiscal_year, splits: [ [ income.id, BigDecimal("200") ], [ other_income.id, BigDecimal("100") ] ])

    expect(receipt.reload.journal_entry.lines.find_by(account: income).credit).to eq(200)
    expect(receipt.journal_entry.lines.find_by(account: bank_gl).debit).to eq(300)
  end
end
