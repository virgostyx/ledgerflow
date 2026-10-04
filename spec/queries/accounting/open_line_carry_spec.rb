require "rails_helper"

# F10: a line carried into the next fiscal year (origin_line_id) is counted once: open in the year it came from until the carried line exists, then only the
# carried one is. It keeps its due date, so the aged balance of the first day of the new year is the one of the last day of the old.
RSpec.describe "Open lines carried forward" do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :sale) }
  let!(:customers) { create(:account, :customer, code: "400000", reconcilable: true) }
  let!(:revenue)   { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }
  let(:alice) { create(:partner, name: "Alice", payment_terms_days: 30) }
  let(:year_end) { fiscal_year.end_date }
  let!(:next_year) { create(:fiscal_year, status: :pre_closing, year: fiscal_year.year + 1, start_date: year_end + 1, end_date: ((year_end + 1) >> 12) - 1) }

  def post_line(year, date, amount, due: nil, origin: nil, partner: alice)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    line = create(:journal_entry_line, journal_entry: entry, account: customers, partner: partner, debit: amount, credit: 0, due_date: due, origin_line_id: origin&.id)
    create(:journal_entry_line, journal_entry: entry, account: revenue, debit: 0, credit: amount)
    entry.post!
    line
  end

  def aged(as_of) = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: as_of).call.to_h { |r| [ r.partner_name, r.total ] }

  it "dates a line by its own due date when it has one, else by its entry date and the terms of the partner" do
    carried = post_line(next_year, year_end + 1, 100, due: year_end - 10)
    plain   = post_line(fiscal_year, year_end - 5, 50)

    due = Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: year_end + 1).call.to_h { |r| [ r.line_id, r.due_date ] }
    expect(due[carried.id]).to eq(year_end - 10)
    expect(due[plain.id]).to eq(year_end - 5 + 30)
  end

  it "counts the original while the carried line does not exist yet, and only the carried one afterwards" do
    original = post_line(fiscal_year, year_end - 20, 100)
    carried = post_line(next_year, year_end + 1, 100, due: original.journal_entry.entry_date + 30, origin: original)

    expect(Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: year_end).call.map(&:line_id)).to eq([ original.id ])
    expect(Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: year_end + 1).call.map(&:line_id)).to eq([ carried.id ])
  end

  it "gives the same aged balance, partner by partner, on the last day and on the first day of the next year (criterion 3)" do
    bob = create(:partner, name: "Bob", payment_terms_days: 15)
    a = post_line(fiscal_year, year_end - 40, 100)
    b = post_line(fiscal_year, year_end - 3, 70, partner: bob)
    post_line(next_year, year_end + 1, 100, due: year_end - 40 + 30, origin: a)
    post_line(next_year, year_end + 1, 70, due: year_end - 3 + 15, origin: b, partner: bob)

    expect(aged(year_end + 1)).to eq(aged(year_end))
    expect(aged(year_end).values.sum).to eq(170)
  end

  it "keeps the bucket: an invoice 70 days overdue on the last day is 71 days overdue a day later, in the same bucket" do
    original = post_line(fiscal_year, year_end - 100, 100) # due 30 days later: 70 days overdue on the last day
    post_line(next_year, year_end + 1, 100, due: year_end - 70, origin: original)
    before = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: year_end).call.sole
    after  = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: year_end + 1).call.sole

    expect([ before.days_61_90, after.days_61_90 ]).to eq([ 100, 100 ])
    expect(after.total).to eq(before.total)
  end

  describe "lettering" do
    let(:bank) { create(:account, code: "550000", account_type: :asset, normal_balance: :debit) }

    def payment(year, date, amount)
      entry = create(:journal_entry, :draft, journal: journal, fiscal_year: year, entry_date: date)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: bank, debit: amount, credit: 0)
      line = create(:journal_entry_line, journal_entry: entry, account: customers, partner: alice, debit: 0, credit: amount)
      entry.post!
      line
    end

    it "refuses to letter a line that was carried, and says to letter the carried one" do
      original = post_line(fiscal_year, year_end - 20, 100)
      post_line(next_year, year_end + 1, 100, due: year_end + 10, origin: original)
      result = Accounting::LetterLines.call(lines: [ original, payment(next_year, year_end + 5, 100) ])

      expect(result).to be_failure
      expect(result.message).to match(/carried.*next fiscal year/i)
    end

    it "letters the carried line, and settles the invoice that the original belonged to" do
      invoice = create(:invoice, :posted, invoice_type: :customer, partner: alice, fiscal_year: fiscal_year, journal: journal)
      original = post_line(fiscal_year, year_end - 20, 100)
      invoice.update_columns(journal_entry_id: original.journal_entry_id)
      carried = post_line(next_year, year_end + 1, 100, due: year_end + 10, origin: original)

      expect(Accounting::LetterLines.call(lines: [ carried, payment(next_year, year_end + 5, 100) ])).to be_success
      expect(invoice.reload).to be_paid
    end
  end
end
