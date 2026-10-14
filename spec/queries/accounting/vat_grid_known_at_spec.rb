require "rails_helper"

# B03a: the grids of the VAT return as they were known at an instant (R09): what was validated later is absent, and an entry reversed since still counts until its reversal.
RSpec.describe Accounting::VatGridQuery, "as known at an instant" do
  include_context "with_open_fiscal_year"

  let!(:journal) { create(:journal, :purchase) }
  let!(:vat_account) { create(:account, code: "451000", label_fr: "VAT to pay") }
  let!(:bank_side) { create(:account, code: "611000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let(:user) { create(:user) }
  let(:period) { { period_start: fiscal_year.start_date, period_end: fiscal_year.start_date + 60 } }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_vat(amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: "V-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: vat_account, debit: BigDecimal("1000"), credit: 0, vat_code: 1, vat_amount: amount)
    create(:journal_entry_line, journal_entry: entry, account: bank_side, debit: 0, credit: BigDecimal("1000"))
    entry.post!
    next_posting_instant
    entry.reload
  end

  def grids(known_at = nil) = described_class.call(fiscal_year_id: fiscal_year.id, known_at: known_at, **period)

  it "is the current return when the instant is now or later" do
    post_vat(BigDecimal("210"))

    expect(grids(1.hour.from_now)).to eq(grids)
  end

  it "leaves out what was validated after the instant" do
    post_vat(BigDecimal("210"))
    at = instant
    post_vat(BigDecimal("105"))

    expect(grids(at)["01"]).to eq(210)
    expect(grids["01"]).to eq(315)
  end

  it "still counts an entry reversed since, until its reversal" do
    original = post_vat(BigDecimal("210"))
    before_reversal = instant
    Accounting::ReverseJournalEntry.call(entry: original, reason: "mistake", user: user).tap { |r| raise r.message if r.failure? }

    expect(original.reload).to be_reversed
    expect(grids(before_reversal)["01"]).to eq(210)
    expect(grids["01"]).to be_nil
  end

  it "is refused before the history" do
    expect { grids(3.days.ago) }.to raise_error(Accounting::KnownAt::Refused)
  end
end
