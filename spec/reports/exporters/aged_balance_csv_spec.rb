require "rails_helper"

RSpec.describe Reports::Exporters::AgedBalanceCsv do
  let(:row_class) { Accounting::AgedBalanceQuery::Row }
  let(:zero) { BigDecimal("0") }
  let(:row) do
    row_class.new(partner_id: 1, partner_name: "Acme", not_due: BigDecimal("100"), days_1_30: zero, days_31_60: zero,
                  days_61_90: zero, over_90: zero, unallocated: zero, total: BigDecimal("100"))
  end
  let(:totals) { row }

  def parse(output) = CSV.parse(output.delete_prefix("﻿"), headers: true).map(&:to_h)

  it "starts with a BOM and writes one line per row followed by a totals line" do
    output = described_class.call(rows: [ row ], totals: totals)

    expect(output).to start_with("﻿")
    lines = parse(output)
    expect(lines.map { |l| l["Partner"] }).to eq([ "Acme", "Totals" ])
    expect(lines.last["Total"]).to eq("100.00")
  end

  it "labels a row without partner" do
    anonymous = row.dup.tap { |r| r.partner_name = nil }

    expect(parse(described_class.call(rows: [ anonymous ], totals: totals)).first["Partner"]).to eq("No partner")
  end
end
