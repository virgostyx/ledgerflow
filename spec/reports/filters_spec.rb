require "rails_helper"

RSpec.describe Reports::Filters, type: :model do
  describe "type casting" do
    it "casts string params (as controllers hand them) to their real types" do
      filters = described_class.new(fiscal_year_id: "12", date_from: "2026-01-01", date_to: "2026-03-31",
                                     journal_ids: %w[1 2], include_drafts: "1")

      expect(filters.fiscal_year_id).to eq(12)
      expect(filters.date_from).to eq(Date.new(2026, 1, 1))
      expect(filters.date_to).to eq(Date.new(2026, 3, 31))
      expect(filters.include_drafts).to eq(true)
    end
  end

  describe "validations" do
    it "is valid with date_from before date_to" do
      expect(described_class.new(date_from: "2026-01-01", date_to: "2026-01-31")).to be_valid
    end

    it "is invalid with date_from after date_to" do
      filters = described_class.new(date_from: "2026-02-01", date_to: "2026-01-01")
      expect(filters).not_to be_valid
      expect(filters.errors[:date_from]).to be_present
    end

    it "is valid without any date filter" do
      expect(described_class.new).to be_valid
    end
  end

  describe "#to_query and .from_query" do
    it "round-trips through a query string" do
      original    = described_class.new(fiscal_year_id: 3, date_from: "2026-01-01", journal_ids: %w[1 2])
      reconstructed = described_class.from_query(original.to_query)

      expect(reconstructed.fiscal_year_id).to eq(3)
      expect(reconstructed.date_from).to eq(Date.new(2026, 1, 1))
      expect(reconstructed.journal_ids).to eq(%w[1 2])
    end
  end

  describe "#as_json" do
    it "serializes to a plain hash" do
      filters = described_class.new(fiscal_year_id: 3, date_from: "2026-01-01")
      expect(filters.as_json).to include("fiscal_year_id" => 3, "date_from" => "2026-01-01")
    end
  end
end
