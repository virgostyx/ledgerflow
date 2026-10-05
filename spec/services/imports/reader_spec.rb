require "rails_helper"

RSpec.describe Imports::Reader do
  def xlsx(rows)
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Data") do |sheet|
      rows.each { |row| sheet.add_row(row) }
    end
    package.to_stream.read
  end

  it "reads a UTF-8 CSV with its separator detected, a BOM and quoted fields" do
    table = described_class.read("﻿code;label\n400000;\"Clients; belges\"\n", filename: "a.csv")
    expect(table.headers).to eq(%w[code label])
    expect(table.rows).to eq([ [ "400000", "Clients; belges" ] ])
  end

  it "detects a comma, a tab and a pipe" do
    expect(described_class.read("a,b\n1,2\n", filename: "a.csv").rows).to eq([ %w[1 2] ])
    expect(described_class.read("a\tb\n1\t2\n", filename: "a.csv").rows).to eq([ %w[1 2] ])
    expect(described_class.read("a|b\n1|2\n", filename: "a.csv").rows).to eq([ %w[1 2] ])
  end

  it "reads a Latin-1 file when it is not valid UTF-8" do
    table = described_class.read("name;city\nJos\xE9;Li\xE8ge\n".b, filename: "a.csv")
    expect(table.rows).to eq([ [ "José", "Liège" ] ])
  end

  it "skips blank lines and keeps the line number of the file for each row" do
    table = described_class.read("a;b\n\n1;2\n;\n3;4\n", filename: "a.csv")
    expect(table.rows).to eq([ %w[1 2], %w[3 4] ])
    expect(table.lines).to eq([ 3, 5 ])
  end

  it "reads the first sheet of an XLSX file: text, numbers and dates" do
    data = xlsx([ %w[date amount label], [ Date.new(2026, 3, 1), 12.5, "Rent" ], [ Date.new(2026, 3, 2), 3, "Tea" ] ])
    table = described_class.read(data, filename: "a.xlsx")
    expect(table.headers).to eq(%w[date amount label])
    expect(table.rows).to eq([ [ "2026-03-01", "12.5", "Rent" ], [ "2026-03-02", "3", "Tea" ] ])
  end

  it "refuses a file that is neither" do
    expect { described_class.read("PK garbage", filename: "a.xlsx") }.to raise_error(Imports::Reader::Unreadable)
    expect { described_class.read("", filename: "a.csv") }.to raise_error(Imports::Reader::Unreadable, /empty/)
  end

  it "refuses a file with too many rows" do
    stub_const("Imports::Reader::MAX_ROWS", 2)
    expect { described_class.read("a\n1\n2\n3\n", filename: "a.csv") }.to raise_error(Imports::Reader::Unreadable, /more than 2 rows/)
  end
end
