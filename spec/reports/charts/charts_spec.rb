require "rails_helper"

RSpec.describe "Charts builders" do
  it "Sparkline plots the given points and carries no axis" do
    option = Charts::Sparkline.call([ [ "2026-01", BigDecimal("10.5") ], [ "2026-02", nil ] ])
    expect(option[:series].first[:data]).to eq([ 10.5, nil ])
    expect(option[:xAxis][:data]).to eq(%w[2026-01 2026-02])
    expect(option[:xAxis][:show]).to be(false)
  end

  describe Charts::AgedBuckets do
    let(:rows) do
      [ 300, 100, 200 ].each_with_index.map do |total, i|
        Accounting::AgedBalanceQuery::Row.new(partner_name: "P#{i}", not_due: BigDecimal(total), days_1_30: 0, days_31_60: 0,
                                              days_61_90: 0, over_90: 0, unallocated: 0, total: BigDecimal(total))
      end
    end

    it "gives one bar per bucket from the report totals" do
      option = described_class.buckets(Accounting::AgedBalanceQuery.totals(rows))
      expect(option[:series].first[:data].map { |d| d[:value] }).to eq([ 600.0, 0.0, 0.0, 0.0, 0.0 ])
    end

    it "keeps the ten biggest balances, largest last (top of the chart)" do
      option = described_class.top_partners(rows, limit: 2)
      expect(option[:yAxis][:data]).to eq(%w[P2 P0])
    end
  end

  describe Charts::MonthlyIncome do
    def row(code, months) = Accounting::AnnualAccounts::MonthlyRow.new(code: code, label: code, level: 1, months: months)

    it "sums income and charges rubrics per month and plots the period result" do
      rows = [ row("70/76A", [ 100 ] + [ 0 ] * 11), row("75/76B", [ 5 ] + [ 0 ] * 11), row("76", [ 0 ] * 12),
               row("60/66A", [ 40 ] + [ 0 ] * 11), row("65/66B", [ 0 ] * 12), row("66", [ 0 ] * 12), row("9904", [ 65 ] + [ 0 ] * 11) ]
      income, expenses, result = described_class.call(rows)[:series]
      expect([ income[:data].first, expenses[:data].first, result[:data].first ]).to eq([ 105.0, 40.0, 65.0 ])
      expect(income[:data].size).to eq(12)
    end
  end
end
