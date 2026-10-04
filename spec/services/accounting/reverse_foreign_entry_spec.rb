require "rails_helper"

# F11: the reversal of an entry in a foreign currency is in that currency too: same currency and rate, the amount in currency of the opposite sign, so that the
# pair cancels out in the currency and is lettered by itself (a pair in two currencies could not be).
RSpec.describe Accounting::ReverseJournalEntry, "of an entry in a foreign currency" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :sale) }
  let!(:customers) { create(:account, :customer, code: "400000", reconcilable: true) }
  let!(:revenue)   { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }
  let(:partner) { create(:partner, name: "Acme Ltd") }
  let(:entry) do
    e = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: e, account: customers, partner: partner, debit: BigDecimal("909.09"), credit: 0, currency: "USD", amount_currency: BigDecimal("1000"), exchange_rate: BigDecimal("1.1"))
    create(:journal_entry_line, journal_entry: e, account: revenue, debit: 0, credit: BigDecimal("909.09"), currency: "USD", amount_currency: BigDecimal("-1000"), exchange_rate: BigDecimal("1.1"))
    Accounting::PostJournalEntry.call!(entry: e)
    e.reload
  end

  it "carries the currency and the rate, with the amount in currency of the opposite sign" do
    reversal = described_class.call(entry: entry, reason: "Wrong customer")[:reversal]
    line = reversal.lines.find_by(account: customers)

    expect(line).to have_attributes(credit: BigDecimal("909.09"), currency: "USD", amount_currency: BigDecimal("-1000"), exchange_rate: BigDecimal("1.1"))
    expect(reversal.lines.sum(:amount_currency)).to eq(0)
  end

  it "letters the pair by itself, in USD, with no exchange difference, so that nothing is left open" do
    described_class.call(entry: entry, reason: "Wrong customer")

    original = entry.lines.find_by(account: customers).reload
    expect(original.lettering_id).to be_present
    expect(Accounting::JournalEntry.where(source_type: Accounting::JournalEntry::FX_SOURCE)).to be_empty
    expect(Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: Date.current).call).to be_empty
  end
end
