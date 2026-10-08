require "rails_helper"

RSpec.describe Agent::Documents::Grounding do
  let(:text) { "Facture 12/2026\nSociété Générale Dupont\nTVA BE 0123.456.749\nIBAN BE68 5390 0754 7034\nDate : 3 mars 2026\nTotal 1.210,50 EUR\f2e page\nÉchéance 2026-04-02" }
  let(:grounding) { described_class.new(text) }

  it "finds an amount however it is written, and says on which page and line" do
    found = grounding.find("total", "1210.50")

    expect(found).to have_attributes(page: 1, snippet: "Total 1.210,50 EUR")
    expect(grounding.find("total", "1210.51")).to be_nil
  end

  it "finds a date in any of the usual writings, on the right page" do
    expect(grounding.find("invoice_date", "2026-03-03")&.page).to eq(1)
    expect(grounding.find("due_date", "2026-04-02")&.page).to eq(2)
    expect(grounding.find("due_date", "2026-04-03")).to be_nil
  end

  it "finds an identifier without its spaces and dots, and a name without its accents" do
    expect(grounding.find("supplier_vat", "BE0123456749")).to be_present
    expect(grounding.find("iban", "BE68539007547034")).to be_present
    expect(grounding.find("supplier_name", "Societe Generale Dupont")).to be_present
    expect(grounding.find("supplier_name", "Autre Société")).to be_nil
  end

  it "finds a currency by its code or its symbol" do
    expect(grounding.find("currency", "EUR")).to be_present
    expect(grounding.find("currency", "USD")).to be_nil
  end

  it "finds nothing for an empty value, or one too short to mean anything" do
    expect(grounding.find("invoice_number", "")).to be_nil
    expect(grounding.find("invoice_number", "1")).to be_nil
  end
end
