require "rails_helper"

# F11, entries in a foreign currency: balanced in EUR and, for a document wholly in one currency, in that currency too; the rounding left by the
# conversion goes to a line of its own; the rate is frozen on the lines (criteria 1 and 4 of the conversion rules).
RSpec.describe "Entries in a foreign currency" do
  include_context "with_open_fiscal_year"

  let(:journal)  { create(:journal, :sale) }
  let!(:customers) { create(:account, :customer, reconcilable: true) }
  let!(:revenue)   { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }
  let!(:fx_loss)   { create(:account, code: "651200", account_type: :expense, normal_balance: :debit) }
  let!(:fx_gain)   { create(:account, code: "751100", account_type: :revenue, normal_balance: :credit) }

  # lines: [account, side, eur, foreign (unsigned, nil for a EUR line), currency, rate]
  def entry_with(*lines)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    lines.each do |account, side, eur, foreign, currency, rate|
      attrs = { journal_entry: entry, account: account, side => BigDecimal(eur.to_s), (side == :debit ? :credit : :debit) => BigDecimal("0") }
      attrs.merge!(currency: currency, amount_currency: (side == :debit ? 1 : -1) * BigDecimal(foreign.to_s), exchange_rate: BigDecimal(rate.to_s)) if foreign
      create(:journal_entry_line, **attrs)
    end
    entry
  end

  def post(entry) = Accounting::PostJournalEntry.call(entry: entry)

  describe "a document wholly in one currency" do
    it "of 1 000 USD at 1.10 is 909.09 EUR on both sides, and 1 000 USD on both sides (criterion 1)" do
      entry = entry_with([ customers, :debit, "909.09", "1000", "USD", "1.10" ], [ revenue, :credit, "909.09", "1000", "USD", "1.10" ])

      expect(post(entry)).to be_success
      lines = entry.reload.lines
      expect(lines.sum(:debit)).to eq(lines.sum(:credit))
      expect(lines.sum(:amount_currency)).to eq(0)
      expect(lines.find_by(account: customers).amount_currency).to eq(BigDecimal("1000"))
      expect(lines.find_by(account: revenue).amount_currency).to eq(BigDecimal("-1000"))
    end

    it "is refused when it does not balance in its own currency, even if the euros do" do
      entry = entry_with([ customers, :debit, "90.91", "100", "USD", "1.10" ], [ revenue, :credit, "90.91", "99", "USD", "1.0889" ])
      result = post(entry)
      expect(result).to be_failure
      expect(result.message).to match(/USD/)
    end
  end

  describe "the rounding of the conversion" do
    it "puts a cent left by converting line by line on a line of its own, on the exchange difference account of the right side" do
      # 100.00 USD / 7 = 14.29 EUR ; 33.33 / 7 = 4.76 and 66.67 / 7 = 9.52: the credits are a cent short
      entry = entry_with([ customers, :debit, "14.29", "100", "USD", "7" ], [ revenue, :credit, "4.76", "33.33", "USD", "7" ], [ revenue, :credit, "9.52", "66.67", "USD", "7" ])

      expect(post(entry)).to be_success
      lines = entry.reload.lines
      expect(lines.sum(:debit)).to eq(lines.sum(:credit))
      rounding = lines.find_by(account: fx_gain)
      expect(rounding).to have_attributes(credit: BigDecimal("0.01"), currency: "EUR", amount_currency: nil)
      expect(rounding.label).to match(/rounding/i)
    end

    it "takes the loss account when the debits are a cent short" do
      entry = entry_with([ customers, :debit, "14.28", "100", "USD", "7" ], [ revenue, :credit, "14.29", "100", "USD", "7" ])
      expect(post(entry)).to be_success
      expect(entry.reload.lines.find_by(account: fx_loss)).to have_attributes(debit: BigDecimal("0.01"))
    end

    it "adds nothing when the euros already balance" do
      entry = entry_with([ customers, :debit, "909.09", "1000", "USD", "1.10" ], [ revenue, :credit, "909.09", "1000", "USD", "1.10" ])
      post(entry)
      expect(entry.reload.lines.count).to eq(2)
    end

    it "does not hide a real imbalance: more than 2 cents is refused" do
      entry = entry_with([ customers, :debit, "14.29", "100", "USD", "7" ], [ revenue, :credit, "14.20", "100", "USD", "7" ])
      expect(post(entry)).to be_failure
    end

    it "is not added to an entry in EUR only" do
      entry = entry_with([ customers, :debit, "10.00" ], [ revenue, :credit, "9.99" ])
      expect(post(entry)).to be_failure
    end

    it "refuses with a message when the exchange difference account does not exist" do
      fx_gain.destroy!
      entry = entry_with([ customers, :debit, "14.29", "100", "USD", "7" ], [ revenue, :credit, "4.76", "33.33", "USD", "7" ], [ revenue, :credit, "9.52", "66.67", "USD", "7" ])
      result = post(entry)
      expect(result).to be_failure
      expect(result.message).to include("751100")
    end
  end

  describe "what a foreign line must carry" do
    it "needs a foreign amount" do
      entry = entry_with([ customers, :debit, "10.00" ], [ revenue, :credit, "10.00" ])
      entry.lines.first.update_columns(currency: "USD", exchange_rate: 1.1)
      result = post(entry)
      expect(result).to be_failure
      expect(result.message).to match(/USD.*amount/i)
    end

    it "needs a rate that is positive" do
      entry = entry_with([ customers, :debit, "10.00", "11", "USD", "1.10" ], [ revenue, :credit, "10.00" ])
      entry.lines.first.update_columns(exchange_rate: 0)
      expect(post(entry)).to be_failure
    end

    it "needs the sign of the foreign amount to be the side of the line" do
      entry = entry_with([ customers, :debit, "909.09", "1000", "USD", "1.10" ], [ revenue, :credit, "909.09", "1000", "USD", "1.10" ])
      entry.lines.find_by(account: customers).update_columns(amount_currency: -1000)
      result = post(entry)
      expect(result).to be_failure
      expect(result.message).to match(/sign/i)
    end

    it "must agree with the euros at the rate, to the cent" do
      entry = entry_with([ customers, :debit, "900.00", "1000", "USD", "1.10" ], [ revenue, :credit, "900.00", "1000", "USD", "1.10" ])
      result = post(entry)
      expect(result).to be_failure
      expect(result.message).to match(/909\.09/)
    end

    it "accepts a euro amount a cent from the rate's (a bank gives the euros, the rate is derived)" do
      entry = entry_with([ customers, :debit, "909.10", "1000", "USD", "1.10" ], [ revenue, :credit, "909.10", "1000", "USD", "1.10" ])
      expect(post(entry)).to be_success
    end
  end

  describe "the decimals of the currency" do
    {
      "JPY" => [ "1000.5", "1000" ],
      "USD" => [ "10.001", "10.00" ],
      "BHD" => [ "10.0001", "10.001" ]
    }.each do |code, (bad, good)|
      it "refuses #{bad} #{code} and accepts #{good} #{code}" do
        rate = BigDecimal("1")
        eur = ->(foreign) { Fx::Convert.to_eur(BigDecimal(foreign), rate) }
        refused = entry_with([ customers, :debit, eur.(bad), bad, code, 1 ], [ revenue, :credit, eur.(bad), bad, code, 1 ])
        result = post(refused)
        expect(result).to be_failure
        expect(result.message).to include(code)

        accepted = entry_with([ customers, :debit, eur.(good), good, code, 1 ], [ revenue, :credit, eur.(good), good, code, 1 ])
        expect(post(accepted)).to be_success
      end
    end
  end

  it "leaves an entry in two currencies to balance in EUR only" do
    entry = entry_with([ customers, :debit, "909.09", "1000", "USD", "1.10" ], [ revenue, :credit, "909.09", "20000", "ZMW", "22.00" ])
    expect(post(entry)).to be_success
  end
end
