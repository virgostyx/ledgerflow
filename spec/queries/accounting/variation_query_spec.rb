require "rails_helper"

RSpec.describe Accounting::VariationQuery do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:journal) { create(:journal, :purchase) }
  let(:supplier_a) { create(:partner, :supplier, name: "Fournisseur A", vat_number: nil) }
  let(:supplier_b) { create(:partner, :supplier, name: "Fournisseur B", vat_number: nil) }

  def post(date, amount, partner, account: account_604)
    entry = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: date, status: :draft, reference: nil, description: "Cost")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account, debit: BigDecimal(amount), credit: 0, label: "Cost")
    create(:journal_entry_line, journal_entry: entry, account: account_440, partner: partner, debit: 0, credit: BigDecimal(amount))
    Accounting::PostJournalEntry.call!(entry: entry)
  end

  let(:first)  { fiscal_year.start_date..(fiscal_year.start_date + 29) }
  let(:second) { (fiscal_year.start_date + 30)..(fiscal_year.start_date + 59) }

  before do
    post(first.begin + 1, "100.00", supplier_a)
    post(second.begin + 1, "100.00", supplier_a)
    post(second.begin + 5, "900.00", supplier_b) # the one-off movement that explains the change
  end

  it "ranks the contributors to the change, with both periods, in decimals" do
    result = described_class.new(account_prefix: "604", first: first, second: second, group_by: "partner").call
    # the cost side carries no partner: group by account
    by_account = described_class.new(account_prefix: "604", first: first, second: second).call

    expect(by_account.rows.map(&:key)).to eq([ "604000" ])
    expect(by_account.rows.first).to have_attributes(first: BigDecimal("100.00"), second: BigDecimal("1000.00"), change: BigDecimal("900.00"), largest_line: BigDecimal("900.00"))
    expect([ by_account.first_total, by_account.second_total, by_account.change_total ]).to eq([ BigDecimal("100.00"), BigDecimal("1000.00"), BigDecimal("900.00") ])
    expect(result.rows).to be_a(Array)
  end

  it "groups by partner on the side that carries one, and finds the main contributor" do
    result = described_class.new(account_prefix: "440", first: first, second: second, group_by: "partner").call

    expect(result.rows.first).to have_attributes(label: "Fournisseur B", first: BigDecimal("0"), second: BigDecimal("-900.00"), change: BigDecimal("-900.00"))
    expect(result.rows.map(&:label)).to eq([ "Fournisseur B", "Fournisseur A" ])
  end

  it "groups by calendar month, so that the same month of two periods is compared" do
    result = described_class.new(account_prefix: "604", first: first, second: second, group_by: "month").call

    expect(result.rows.size).to eq(2)
    expect(result.rows.map { |row| row.change.abs }).to eq([ BigDecimal("1000.00"), BigDecimal("100.00") ])
  end

  it "lists only the biggest changes and sums the others" do
    post(second.begin + 7, "10.00", supplier_a, account: account_651200)
    result = described_class.new(account_prefix: "6", first: first, second: second, limit: 1).call

    expect(result.rows.size).to eq(1)
    expect(result.rows.first.key).to eq("604000")
    expect(result.others_change).to eq(BigDecimal("10.00"))
    expect(result.groups).to eq(2)
  end

  it "takes only validated entries and refuses a grouping it does not know" do
    draft = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: second.begin + 3, status: :draft, reference: nil, description: "Draft")
    create(:journal_entry_line, journal_entry: draft, account: account_604, debit: BigDecimal("5000.00"), credit: 0, label: "Draft")

    expect(described_class.new(account_prefix: "604", first: first, second: second).call.second_total).to eq(BigDecimal("1000.00"))
    expect { described_class.new(account_prefix: "6", first: first, second: second, group_by: "nope") }.to raise_error(ArgumentError)
  end
end
