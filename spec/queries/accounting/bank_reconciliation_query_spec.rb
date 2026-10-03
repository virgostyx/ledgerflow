require "rails_helper"

# R06 (docs/dev/reports/spec.md §8): B (relevé) + BN (comptabilisé, pas sur le relevé)
# − SN (sur le relevé, pas comptabilisé) doit égaler A (solde comptable réel).
RSpec.describe Accounting::BankReconciliationQuery, type: :query do
  include_context "with_open_fiscal_year"

  let(:as_of)         { Date.current }
  let(:bank_account)   { create(:bank_account, entity: entity) }
  let(:gl_account)     { bank_account.journal.default_account }
  let(:other_account)  { create(:account, code: "440000", account_type: :liability, normal_balance: :credit) }
  let(:journal)        { create(:journal, :purchase) }

  def post_entry(amount:, side: :debit, entry_date: as_of)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: entry_date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    other = side == :debit ? :credit : :debit
    create(:journal_entry_line, journal_entry: entry, account: gl_account,
           side => BigDecimal(amount.to_s), other => 0)
    create(:journal_entry_line, journal_entry: entry, account: other_account,
           other => BigDecimal(amount.to_s), side => 0)
    entry.post!
    entry
  end

  def post_transaction(amount:, journal_entry: nil, transaction_date: as_of)
    create(:bank_transaction, bank_account: bank_account, amount: BigDecimal(amount.to_s),
           transaction_date: transaction_date, journal_entry: journal_entry,
           status: journal_entry ? :reconciled : :pending)
  end

  subject(:result) { described_class.new(bank_account: bank_account, as_of: as_of).call }

  it "has a zero gap when everything is reconciled" do
    entry = post_entry(amount: 100, side: :debit)
    post_transaction(amount: 100, journal_entry: entry)

    expect(result.bn).to be_empty
    expect(result.sn).to be_empty
    expect(result.gap).to eq(0)
  end

  it "puts a booked-but-not-on-statement entry in BN, gap still zero" do
    post_entry(amount: 80, side: :debit)

    expect(result.bn.size).to eq(1)
    expect(result.bn.first.amount).to eq(BigDecimal("80"))
    expect(result.sn).to be_empty
    expect(result.gap).to eq(0)
  end

  it "puts an unbooked statement operation in SN, gap still zero" do
    post_transaction(amount: -45)

    expect(result.sn.size).to eq(1)
    expect(result.sn.first.amount).to eq(BigDecimal("-45"))
    expect(result.bn).to be_empty
    expect(result.gap).to eq(0)
  end

  it "keeps a grouped payment (one entry, one transaction) out of both BN and SN" do
    entry = post_entry(amount: 250, side: :credit)
    post_transaction(amount: -250, journal_entry: entry)

    expect(result.bn).to be_empty
    expect(result.sn).to be_empty
  end

  it "reproduces the state as of a past date retroactively" do
    entry = post_entry(amount: 60, side: :debit, entry_date: as_of - 5)
    post_transaction(amount: 60, journal_entry: entry, transaction_date: as_of - 1)

    past = described_class.new(bank_account: bank_account, as_of: as_of - 3).call
    expect(past.bn.size).to eq(1) # booked, but the matching transaction is dated after this as_of
  end

  # No "entity scoped report" shared example here: unlike the other queries, this one
  # takes a specific bank_account record rather than a bare id/date range, and
  # acts_as_tenant already makes a bank_account from another entity unreachable —
  # there's no shared foreign key to leak through.

  describe "with imported statements (F02)" do
    let(:batch) { Accounting::ImportBatch.create!(parser: "coda", file_sha256: "x", result: "imported") }

    def statement(old:, new:, on:, **attrs)
      Accounting::BankStatement.create!(bank_account: bank_account, import_batch: batch, old_balance: old, new_balance: new, new_balance_date: on, old_balance_date: on - 1, **attrs)
    end

    it "takes the closing balance of the last statement as the statement balance, the opening balance of the bank being known" do
      statement(old: 1000, new: 1250, on: as_of - 5)
      statement(old: 1250, new: 1100, on: as_of - 1)

      expect(described_class.new(bank_account: bank_account, as_of: as_of).call.statement_balance).to eq(BigDecimal("1100"))
    end

    it "adds the lines that came without a statement after it, and ignores those before" do
      statement(old: 1000, new: 1250, on: as_of - 5)
      post_transaction(amount: 40, transaction_date: as_of - 9)  # before the statement: already in its opening balance
      post_transaction(amount: 25, transaction_date: as_of - 2)  # after it

      expect(described_class.new(bank_account: bank_account, as_of: as_of).call.statement_balance).to eq(BigDecimal("1275"))
    end

    it "keeps the flat sum of the lines when there is no statement up to the date" do
      statement(old: 1000, new: 1250, on: as_of + 3)
      post_transaction(amount: 40)

      expect(described_class.new(bank_account: bank_account, as_of: as_of).call.statement_balance).to eq(BigDecimal("40"))
    end

    it "lists the statements whose chain is broken and those that do not add up" do
      ok = statement(old: 1000, new: 1250, on: as_of - 5, chain_gap: nil)
      broken = statement(old: 900, new: 1100, on: as_of - 1, chain_gap: BigDecimal("-350"))
      unbalanced = statement(old: 1100, new: 1500, on: as_of, chain_gap: BigDecimal("0"), status: "to_review", integrity_gap: BigDecimal("400"))

      result = described_class.new(bank_account: bank_account, as_of: as_of).call

      expect(result.chain_breaks).to eq([ broken ])
      expect(result.to_review).to eq([ unbalanced ])
      expect([ ok ]).not_to include(*result.chain_breaks)
    end
  end

  describe "a line whose payment entry is still a draft (F02, matched)" do
    it "counts as on the statement and not yet booked, so the gap stays zero until the entry is validated" do
      draft = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: as_of)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: draft, account: gl_account, debit: 50, credit: 0)
      create(:journal_entry_line, journal_entry: draft, account: other_account, debit: 0, credit: 50)
      create(:bank_transaction, bank_account: bank_account, amount: 50, transaction_date: as_of, journal_entry: draft, status: :matched)

      result = described_class.new(bank_account: bank_account, as_of: as_of).call

      expect(result.sn.map(&:amount)).to eq([ BigDecimal("50") ])
      expect(result.gap).to eq(0)

      Accounting::PostJournalEntry.call(entry: draft)
      after = described_class.new(bank_account: bank_account, as_of: as_of).call

      expect(after.sn).to be_empty
      expect(after.gap).to eq(0)
    end
  end
end
