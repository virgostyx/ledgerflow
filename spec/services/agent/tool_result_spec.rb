require "rails_helper"

RSpec.describe Agent::ToolResult do
  it "gives the envelope every tool answers in: data, totals, currency, as of, filters applied, how many rows, whether it is partial, warnings" do
    result = described_class.build(data: [ { "name" => "ACME" } ], totals: { "total" => "10.00" }, currency: "EUR", as_of: Date.new(2026, 9, 26), filters_applied: { "kind" => "customer" }, warnings: [ "2 lines without a partner" ])

    expect(result).to eq("data" => [ { "name" => "ACME" } ], "totals" => { "total" => "10.00" }, "currency" => "EUR", "as_of" => "2026-09-26",
                         "filters_applied" => { "kind" => "customer" }, "row_count" => 1, "truncated" => false, "warnings" => [ "2 lines without a partner" ])
  end

  describe ".money" do
    it "writes an amount as a decimal string with two decimals, whatever it was given" do
      expect(described_class.money(BigDecimal("1234.5"))).to eq("1234.50")
      expect(described_class.money(BigDecimal("-0.005"))).to eq("-0.01").or eq("0.00").or eq("-0.00")
      expect(described_class.money(12)).to eq("12.00")
      expect(described_class.money("7.1")).to eq("7.10")
      expect(described_class.money(nil)).to eq("0.00")
    end

    it "refuses a float: an amount is never one" do
      expect { described_class.money(1234.5) }.to raise_error(ArgumentError, /Float/)
    end
  end

  describe "the size of a result" do
    let(:rows) { Array.new(400) { |i| { "label" => "Line #{i} " + ("x" * 80), "amount" => "1.00", "ref" => "R02:acc:#{i}" } } }

    it "keeps to about 20 KB: the rows that do not fit are dropped, and it says so with how to narrow the search" do
      result = described_class.build(data: rows, currency: "EUR")

      expect(result.to_json.bytesize).to be <= described_class::MAX_BYTES
      expect(result["truncated"]).to be true
      expect(result["row_count"]).to eq(result["data"].size)
      expect(result["row_count"]).to be < 400
      expect(result["warnings"].join).to include("narrow")
    end

    it "keeps the first rows, in order" do
      result = described_class.build(data: rows)

      expect(result["data"].first).to eq(rows.first)
      expect(result["data"]).to eq(rows.first(result["data"].size))
    end

    it "reports as partial a result its tool already cut" do
      expect(described_class.build(data: [ {} ], truncated: true)["truncated"]).to be true
    end

    it "leaves a small result alone" do
      expect(described_class.build(data: rows.first(3))["truncated"]).to be false
    end
  end
end
