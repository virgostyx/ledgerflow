require "rails_helper"

# F06 step 3: who sent the invoice. VAT number, then enterprise number (BCE), then IBAN; exactly one partner at a level or no guess.
RSpec.describe Peppol::SupplierMatch do
  include_context "with entity"

  def supplier(**attrs) = Peppol::CanonicalInvoice::Party.new(name: "Fournisseur SA", **attrs)

  let!(:known) { create(:partner, partner_type: :supplier, vat_number: "BE0123456749", iban: "BE68539007547034") }

  it "finds the partner by its VAT number" do
    result = described_class.find(supplier(vat: "BE0123456749"))

    expect(result).to have_attributes(partner: known, by: :vat_number, problem: nil)
  end

  it "finds it by the enterprise number when the document gives no VAT number (company identifier of scheme 0208, or the endpoint)" do
    by_company = described_class.find(supplier(company_id: "0123456749", company_scheme: "0208"))
    by_endpoint = described_class.find(supplier(endpoint: "0208:0123.456.749"))

    expect([ by_company, by_endpoint ]).to all(have_attributes(partner: known, by: :enterprise_number))
  end

  it "finds it by IBAN, written however the supplier wrote it" do
    result = described_class.find(supplier(iban: "be68 5390 0754 7034"))

    expect(result).to have_attributes(partner: known, by: :iban)
  end

  it "tries the VAT number first, then the enterprise number, then the IBAN" do
    other = create(:partner, partner_type: :supplier, iban: "FR1420041010050500013M02606")

    result = described_class.find(supplier(vat: "BE0123456749", iban: other.iban))

    expect(result.partner).to eq(known)
  end

  it "does not guess when two partners share the identifier: it is a problem" do
    create(:partner, partner_type: :supplier, iban: "BE68539007547034")

    result = described_class.find(supplier(iban: "BE68539007547034"))

    expect(result.partner).to be_nil
    expect(result.problem).to include("Several partners").and include("iban")
  end

  it "finds nobody when nothing matches, or when the identifiers are not there or not valid" do
    expect(described_class.find(supplier(vat: "BE0999999999")).partner).to be_nil
    expect(described_class.find(supplier(iban: "IBAN32423940")).partner).to be_nil
    expect(described_class.find(supplier).partner).to be_nil
  end
end
