require "rails_helper"

RSpec.describe Reports::Exporters::Csv, type: :model do
  csv_spec_row = Struct.new(:code, :label, :balance)

  let(:result) do
    Reports::Result.new(rows: [
      csv_spec_row.new("600000", "Achats", BigDecimal("1234.5")),
      csv_spec_row.new("700000", "Ventes", BigDecimal("-500"))
    ])
  end
  let(:columns) { [ [ "Code", :code ], [ "Libellé", :label ], [ "Solde", :balance ] ] }

  it "starts with a UTF-8 BOM" do
    expect(described_class.call(result, columns: columns)).to start_with("﻿")
  end

  it "uses ; as the field separator and a comma decimal in fr/nl" do
    csv = described_class.call(result, columns: columns, locale: :fr)
    lines = csv.delete_prefix("﻿").lines
    expect(lines[0].chomp).to eq("Code;Libellé;Solde")
    expect(lines[1].chomp).to eq("600000;Achats;1234,50")
    expect(lines[2].chomp).to eq("700000;Ventes;-500,00")
  end

  it "uses , as the field separator and a dot decimal in en" do
    csv = described_class.call(result, columns: columns, locale: :en)
    lines = csv.delete_prefix("﻿").lines
    expect(lines[0].chomp).to eq("Code,Libellé,Solde")
    expect(lines[1].chomp).to eq("600000,Achats,1234.50")
  end

  it "never mixes a totals row into the data" do
    csv = described_class.call(result, columns: columns)
    expect(csv.lines.size).to eq(1 + result.rows.size)
  end

  it "accepts a proc as a column extractor" do
    columns = [ [ "Code", :code ], [ "Doublé", ->(row) { row.balance * 2 } ] ]
    csv = described_class.call(result, columns: columns, locale: :en)
    expect(csv.lines[1]).to include("2469.00")
  end
end
