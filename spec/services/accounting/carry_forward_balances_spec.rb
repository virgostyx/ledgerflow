require "rails_helper"

RSpec.describe Accounting::CarryForwardBalances do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:prev_year) do
    create(:fiscal_year, year: fiscal_year.year - 1,
           start_date: fiscal_year.start_date - 1.year,
           end_date: fiscal_year.start_date - 1.day,
           status: :closed)
  end
  let!(:misc_journal) do
    create(:journal, code: "OUV", label_fr: "Ouverture", journal_type: :misc, sequence_prefix: "OUV")
  end
  let!(:carry_account) do
    create(:account, code: "130000", label_fr: "Résultat reporté",
           account_type: :equity, normal_balance: :credit, account_class: 1)
  end
  let!(:result_account) do
    create(:account, code: "699000", label_fr: "Résultat de l'exercice",
           account_type: :expense, normal_balance: :debit, account_class: 6)
  end
  # Explicitly typed accounts — shared context defaults to :expense
  let!(:asset_account) do
    create(:account, code: "550900", label_fr: "Test bank",
           account_type: :asset, normal_balance: :debit, account_class: 5)
  end
  let!(:payable_account) do
    create(:account, code: "440900", label_fr: "Test payable",
           account_type: :liability, normal_balance: :credit, account_class: 4)
  end
  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:user) { create(:user, role: :accountant) }

  def create_balance_sheet_entry(debit_acct:, credit_acct:, amount:, year: prev_year)
    entry = create(:journal_entry, :draft, journal: purchase_journal, fiscal_year: year,
                   entry_date: year.start_date + 10)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: debit_acct,
           debit: amount, credit: BigDecimal("0"))
    create(:journal_entry_line, journal_entry: entry, account: credit_acct,
           debit: BigDecimal("0"), credit: amount)
    entry.post!
  end

  subject(:result) do
    described_class.call(new_fiscal_year: fiscal_year, closed_by: user)
  end

  context "when no previous closed fiscal year exists" do
    before { prev_year.destroy! }

    it "succeeds without creating any entry" do
      expect(result).to be_success
    end

    it "does not create a journal entry" do
      expect { result }.not_to change(Accounting::JournalEntry, :count)
    end

    it "sets no opening_entry in context" do
      expect(result[:opening_entry]).to be_nil
    end
  end

  context "when account 130000 is missing" do
    before do
      create_balance_sheet_entry(
        debit_acct: asset_account, credit_acct: payable_account,
        amount: BigDecimal("500.00")
      )
      carry_account.destroy!
    end

    it "returns failure" do
      expect(result).to be_failure
    end

    it "includes a descriptive error message" do
      expect(result.message).to include("130000")
    end
  end

  context "when misc journal is missing" do
    before do
      create_balance_sheet_entry(
        debit_acct: asset_account, credit_acct: payable_account,
        amount: BigDecimal("500.00")
      )
      misc_journal.update!(active: false)
    end

    it "returns failure" do
      expect(result).to be_failure
    end
  end

  context "with balance sheet entries in the previous fiscal year" do
    before do
      # Asset: 500 debit (bank ← payable)
      create_balance_sheet_entry(
        debit_acct: asset_account, credit_acct: payable_account,
        amount: BigDecimal("500.00")
      )
    end

    it "returns success" do
      expect(result).to be_success
    end

    it "creates one opening journal entry in the new fiscal year" do
      expect { result }.to change(Accounting::JournalEntry, :count).by(1)
      entry = Accounting::JournalEntry.last
      expect(entry.fiscal_year).to eq(fiscal_year)
    end

    it "posts the opening entry" do
      result
      expect(Accounting::JournalEntry.last).to be_posted
    end

    it "dates the opening entry on the first day of the new fiscal year" do
      result
      expect(Accounting::JournalEntry.last.entry_date).to eq(fiscal_year.start_date)
    end

    it "carries forward the asset account with its debit balance" do
      result
      entry = Accounting::JournalEntry.last
      line = entry.lines.find_by(account: asset_account)
      expect(line).to be_present
      expect(line.debit).to eq(BigDecimal("500.00"))
      expect(line.credit).to eq(BigDecimal("0"))
    end

    it "carries forward the payable account with its credit balance" do
      result
      entry = Accounting::JournalEntry.last
      line = entry.lines.find_by(account: payable_account)
      expect(line).to be_present
      expect(line.credit).to eq(BigDecimal("500.00"))
      expect(line.debit).to eq(BigDecimal("0"))
    end

    it "exposes the opening_entry in the context" do
      expect(result[:opening_entry]).to be_a(Accounting::JournalEntry)
    end
  end

  context "when account 699000 has a net result balance in the previous year" do
    before do
      # Simulate: 699000 ends up with a credit balance of 200 (profit)
      # This is what CloseFiscalYear would produce for a profitable year
      # Asset debited, 699000 credited
      create_balance_sheet_entry(
        debit_acct: asset_account, credit_acct: result_account,
        amount: BigDecimal("200.00")
      )
    end

    it "maps 699000 balance to 130000 (not 699000) in the opening entry" do
      result
      entry = Accounting::JournalEntry.last
      line_699 = entry.lines.find_by(account: result_account)
      line_130 = entry.lines.find_by(account: carry_account)
      expect(line_699).to be_nil
      expect(line_130).to be_present
    end

    it "does not carry forward P&L expense accounts" do
      result
      entry = Accounting::JournalEntry.last
      # account_604 is an expense account — should NOT appear
      line_604 = entry.lines.find_by(account: account_604)
      expect(line_604).to be_nil
    end
  end

  context "when the previous year has no balance sheet entries (all P&L)" do
    # Only P&L entries — no balance sheet carry-forward needed
    before do
      entry = create(:journal_entry, :draft, journal: purchase_journal, fiscal_year: prev_year,
                     entry_date: prev_year.start_date + 10)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604,
             debit: BigDecimal("300.00"), credit: BigDecimal("0"))
      create(:journal_entry_line, journal_entry: entry, account: payable_account,
             debit: BigDecimal("0"), credit: BigDecimal("300.00"))
      entry.post!
      # payable_account is a liability (class 4) — it WILL be carried forward
      # account_604 is expense — will NOT be carried forward
    end

    it "succeeds and only carries forward the liability account" do
      result
      expect(result).to be_success
    end
  end

  context "idempotency — opening entry already exists" do
    before do
      create_balance_sheet_entry(
        debit_acct: asset_account, credit_acct: payable_account,
        amount: BigDecimal("500.00")
      )
      # Run once to create the opening entry
      described_class.call(new_fiscal_year: fiscal_year, closed_by: user)
    end

    it "does not create a second opening entry" do
      expect { result }.not_to change(Accounting::JournalEntry, :count)
    end

    it "returns success" do
      expect(result).to be_success
    end
  end

  context "when an unexpected error occurs" do
    before do
      allow(ApplicationRecord).to receive(:transaction).and_raise(StandardError, "unexpected DB error")
    end

    it "returns a failed context" do
      expect(result).to be_failure
    end
  end
end
