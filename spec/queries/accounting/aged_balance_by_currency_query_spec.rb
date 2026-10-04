require "rails_helper"

# R04 grouped by currency (F11): what is still open per partner in each currency, in the currency, in the EUR the books carry, and, when asked, valued
# at the closing rate of the date. The EUR total is the one of the aged balance.
RSpec.describe Accounting::AgedBalanceByCurrencyQuery, type: :query do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :sale) }
  let!(:customers) { create(:account, :customer, reconcilable: true) }
  let!(:revenue)   { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }
  let(:alice) { create(:partner, name: "Alice", payment_terms_days: 0) }
  let(:bob)   { create(:partner, name: "Bob", payment_terms_days: 0) }
  let(:as_of) { Date.current }

  def sale(partner:, eur:, foreign: nil, currency: "EUR", rate: nil)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: as_of - 10)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    fx = foreign ? { currency: currency, amount_currency: BigDecimal(foreign), exchange_rate: BigDecimal(rate) } : {}
    line = create(:journal_entry_line, journal_entry: entry, account: customers, partner: partner, debit: BigDecimal(eur), credit: 0, **fx)
    create(:journal_entry_line, journal_entry: entry, account: revenue, debit: 0, credit: BigDecimal(eur), **fx.transform_values { |v| v.is_a?(BigDecimal) && v == BigDecimal(foreign) ? -v : v })
    entry.post!
    line
  end

  def call(**opts) = described_class.new(kind: :customer, as_of: as_of, **opts).call

  before do
    sale(partner: alice, eur: "909.09", foreign: "1000", currency: "USD", rate: "1.1")
    sale(partner: bob, eur: "400.00", foreign: "10000", currency: "ZMW", rate: "25")
    sale(partner: alice, eur: "100.00")
  end

  it "lists each partner in each currency, with the amount in the currency and the euros the books carry, EUR included" do
    rows = call.to_h { |r| [ [ r.currency, r.partner_name ], [ r.foreign_amount, r.booked_eur ] ] }
    expect(rows).to eq(
      [ "EUR", "Alice" ] => [ BigDecimal("100"), BigDecimal("100") ],
      [ "USD", "Alice" ] => [ BigDecimal("1000"), BigDecimal("909.09") ],
      [ "ZMW", "Bob" ]   => [ BigDecimal("10000"), BigDecimal("400") ]
    )
  end

  it "adds up, in EUR, to the total of the aged balance (R04)" do
    r04 = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: as_of).call.sum(&:total)
    expect(call.sum(&:booked_eur)).to eq(r04)
  end

  it "keeps only what is still open: a lettered line is out" do
    line = sale(partner: bob, eur: "50.00")
    payment = sale(partner: bob, eur: "50.00").tap { |l| l.update_columns(debit: 0, credit: 50) }
    lettering = create(:lettering, account: customers, partner: bob)
    Accounting::JournalEntryLine.where(id: [ line.id, payment.id ]).update_all(lettering_id: lettering.id)
    expect(call.select { |r| r.currency == "EUR" && r.partner_name == "Bob" }).to be_empty
  end

  describe "at the closing rate" do
    it "values each foreign amount at the closing rate of the date, EUR at itself" do
      Accounting::ExchangeRate.create!(currency: "USD", rate_date: as_of, rate: "1.25", rate_type: :closing, source: "manual")
      Accounting::ExchangeRate.create!(currency: "ZMW", rate_date: as_of, rate: "20", rate_type: :closing, source: "manual")
      rows = call(at_closing_rate: true).index_by { |r| [ r.currency, r.partner_name ] }

      expect(rows[[ "USD", "Alice" ]]).to have_attributes(rate: BigDecimal("1.25"), revalued_eur: BigDecimal("800"))
      expect(rows[[ "ZMW", "Bob" ]]).to have_attributes(rate: BigDecimal("20"), revalued_eur: BigDecimal("500"))
      expect(rows[[ "EUR", "Alice" ]]).to have_attributes(rate: nil, revalued_eur: BigDecimal("100"))
    end

    it "says there is no rate rather than guessing one" do
      row = call(at_closing_rate: true).find { |r| r.currency == "USD" }
      expect(row).to have_attributes(rate: nil, revalued_eur: nil)
    end

    it "has no revalued amount at all when not asked" do
      expect(call.map(&:revalued_eur).compact).to eq([])
    end
  end
end
