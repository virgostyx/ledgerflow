require "rails_helper"

# R06 (docs/dev/reports/spec.md §8): B (relevé) + BN (comptabilisé, pas sur le relevé)
# − SN (sur le relevé, pas comptabilisé) doit égaler A (solde comptable réel).
RSpec.describe Accounting::BankReconciliationQuery, type: :query, bullet_strict: true do
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
end
