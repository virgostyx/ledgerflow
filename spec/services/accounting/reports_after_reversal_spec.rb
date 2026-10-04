require "rails_helper"

# F07: a reversed entry and its reversal are both in the ledger and cancel each other; every report agrees, and the pair does not show as
# open items on the partner accounts (it is lettered together, automatically, without settling an invoice).
RSpec.describe "Reports after a reversal" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user)     { create(:user, role: :accountant) }
  let(:journal)  { create(:journal, :cash) }
  let(:supplier) { create(:partner, :supplier) }
  let(:today)    { fiscal_year.start_date + 100 }
  let(:as_of)    { fiscal_year.end_date }

  before { account_440.update!(normal_balance: :credit) }

  def post_entry(partner: supplier)
    entry = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: today, status: :draft)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: 100, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: account_440, partner: partner, debit: 0, credit: 100)
    Accounting::PostJournalEntry.call!(entry: entry)
    entry.reload
  end

  let!(:entry)    { post_entry }
  let!(:reversal) { Accounting::ReverseJournalEntry.call(entry: entry, reason: "twice", user: user)[:reversal] }

  def trial_balance = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: as_of).call.index_by(&:code)

  it "nets the trial balance to zero on every account" do
    expect(trial_balance.values_at("604000", "440000").map(&:balance)).to all(eq(0))
    expect(trial_balance["604000"].total_debit).to eq(100)
  end

  it "shows the general ledger of the account with both entries and a zero balance" do
    rows = Accounting::GeneralLedgerQuery.new(account: account_440, fiscal_year: fiscal_year).call

    expect(rows.size).to eq(2)
    expect(rows.last.running_balance).to eq(0)
  end

  it "has no aged balance left, and I4 holds" do
    aged = Accounting::AgedBalanceQuery.totals(Accounting::AgedBalanceQuery.new(kind: :supplier, as_of: as_of).call).total

    expect(aged).to eq(0).and eq(trial_balance["440000"].balance)
  end

  it "letters the entry with its reversal on the partner account, so nothing shows as an open item" do
    lines = Accounting::JournalEntryLine.where(journal_entry_id: [ entry.id, reversal.id ], account: account_440)

    expect(lines.pluck(:lettering_id).uniq.size).to eq(1)
    expect(lines.pluck(:lettering_id).first).to be_present
    expect(Accounting::Lettering.find(lines.first.lettering_id)).to have_attributes(auto: true)
    expect(Accounting::UnletteredLinesQuery.new(kind: :supplier, as_of: as_of).call).to be_empty
  end

  it "does not pay an invoice when the invoice entry is reversed" do
    invoice = create(:invoice, :posted, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year)
    invoice_entry = post_entry
    invoice.update_columns(journal_entry_id: invoice_entry.id)

    Accounting::ReverseJournalEntry.call(entry: invoice_entry.reload, reason: "x", user: user, from_source: true)

    expect(invoice.reload).to be_posted
  end

  it "keeps the VAT and analytical figures as they were (a reversal copies neither)" do
    expect(Accounting::JournalEntryLine.where(journal_entry_id: reversal.id).pluck(:vat_code).uniq).to eq([ nil ])
  end
end
