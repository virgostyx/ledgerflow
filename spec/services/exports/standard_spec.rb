require "rails_helper"

RSpec.describe Exports::Standard do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:journal) { create(:journal, code: "OD", journal_type: :misc) }
  let!(:partner) { create(:partner, name: "Acme, Inc.", vat_number: "BE0417497106", external_ref: "ERP-1") }

  def entry(date, amount, partner: nil, description: nil)
    create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date, description: description).tap do |e|
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: e, account: account_604, debit: amount, credit: 0, label: "Cost; \"quoted\"")
      create(:journal_entry_line, journal_entry: e, account: account_440, partner: partner, debit: 0, credit: amount)
      Accounting::PostJournalEntry.call!(entry: e)
    end
  end

  let(:start) { fiscal_year.start_date }

  def csv(dataset, **opts) = CSV.parse(described_class.new(dataset, **opts).csv.to_a.join, headers: true)

  it "writes the entries with their lines, the schema version first, and what a line needs to be read alone" do
    entry(start + 1, 10, partner: partner, description: "March rent")
    table = csv("entries")

    expect(table.headers.first(3)).to eq(%w[schema_version entry_id reference])
    expect(table.size).to eq(2)
    expect(table.map { |r| r["schema_version"] }.uniq).to eq([ "1" ])
    row = table.find { |r| r["account"] == "440000" }
    expect(row.to_h).to include("entry_date" => (start + 1).iso8601, "journal" => "OD", "status" => "posted", "description" => "March rent",
                                "partner" => "Acme, Inc.", "partner_vat" => "BE0417497106", "debit" => "0.00", "credit" => "10.00", "currency" => "EUR")
    expect(table.find { |r| r["account"] == "604000" }["label"]).to eq("Cost; \"quoted\"")
  end

  it "keeps only the entries of the period asked, bounds included" do
    entry(start + 1, 10)
    entry(start + 10, 20)
    entry(start + 30, 30)

    expect(csv("entries", from: start + 10, to: start + 10).size).to eq(2)
    expect(csv("entries", from: start + 10).size).to eq(4)
    expect(csv("entries", to: start + 10).size).to eq(4)
    expect(csv("entries").size).to eq(6)
  end

  it "writes the chart of accounts, the partners and the journals" do
    expect(csv("accounts").map { |r| r["code"] }).to include("604000", "440000")
    expect(csv("accounts").find { |r| r["code"] == "604000" }.to_h).to include("account_type" => "expense", "normal_balance" => "debit", "active" => "true")
    expect(csv("partners").first.to_h).to include("name" => "Acme, Inc.", "external_ref" => "ERP-1", "payment_terms_days" => "30")
    expect(csv("journals").map { |r| r["code"] }).to include("OD")
  end

  it "writes flat JSON with its schema version, in one document" do
    entry(start + 1, 10)
    json = JSON.parse(described_class.new("entries").json.to_a.join)

    expect(json).to include("schema_version" => 1, "dataset" => "entries")
    expect(json["generated_at"]).to be_present
    expect(json["rows"].size).to eq(2)
    expect(json["rows"].first.keys).to eq(described_class.new("entries").headers)
    expect(json["rows"].first["debit"]).to be_a(String) # amounts as text: no float on the way
  end

  it "writes an XLSX workbook whose first sheet holds the header and the rows" do
    entry(start + 1, 10)
    table = Imports::Reader.read(described_class.new("entries").xlsx, filename: "x.xlsx")

    expect(table.headers).to eq([ "schema_version" ] + described_class.new("entries").headers)
    expect(table.rows.size).to eq(2)
  end

  it "refuses an XLSX that would be too big to build in memory, pointing to the CSV" do
    stub_const("Exports::Standard::XLSX_MAX_ROWS", 1)
    entry(start + 1, 10)
    expect { described_class.new("entries").xlsx }.to raise_error(Exports::Standard::TooLarge, /CSV/)
  end

  it "streams in batches: it never holds more than a batch of rows" do
    stub_const("Exports::Standard::BATCH", 2)
    3.times { |i| entry(start + i + 1, 10 + i) }
    chunks = described_class.new("entries").csv.to_a

    expect(chunks.size).to be > 2
    expect(CSV.parse(chunks.join, headers: true).size).to eq(6)
  end

  it "refuses an unknown dataset, and a period that ends before it starts" do
    expect { described_class.new("secrets") }.to raise_error(ArgumentError, /Unknown dataset/)
    expect { described_class.new("entries", from: start + 5, to: start) }.to raise_error(ArgumentError, /before/)
  end

  it "has a dictionary of every column, published in docs/exports.md as it stands" do
    described_class::DATASETS.each do |name, spec|
      expect(Exports::Dictionary::COLUMNS.fetch(name).keys).to eq(spec[:columns].keys), "dictionary of #{name}"
    end
    expect(Rails.root.join("docs/exports.md").read).to eq(Exports::Dictionary.markdown)
  end
end
