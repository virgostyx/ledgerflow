require "rails_helper"

RSpec.describe Peppol::UblInvoiceBuilder do
  include_context "with_open_fiscal_year"

  let(:partner) do
    create(:partner, :with_vat, name: "Acme SA",
           partner_type: :customer, country: "BE")
  end
  let(:invoice) do
    create(:invoice, :posted,
           partner: partner, fiscal_year: fiscal_year,
           invoice_number: "VTE2025/0001",
           invoice_date: Date.new(2025, 1, 15),
           due_date: Date.new(2025, 2, 14),
           currency: "EUR")
  end

  before do
    account = create(:account, code: "700000")
    create(:invoice_line, invoice: invoice, account: account,
           description: "Prestation de service", quantity: 2,
           unit_price: "500.00", vat_rate: "21.00", position: 1)
    invoice.compute_totals
    invoice.save!
  end

  subject(:xml) { described_class.new(invoice).build }

  it "retourne une chaîne XML" do
    expect(xml).to be_a(String)
  end

  it "contient le namespace UBL Invoice-2" do
    expect(xml).to include("urn:oasis:names:specification:ubl:schema:xsd:Invoice-2")
  end

  it "contient le CustomizationID Peppol BIS 3.0" do
    expect(xml).to include("urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0")
  end

  it "contient le ProfileID Peppol" do
    expect(xml).to include("urn:fdc:peppol.eu:2017:poacc:billing:01:1.0")
  end

  it "contient le numéro de facture" do
    expect(xml).to include("VTE2025/0001")
  end

  it "contient la date d'émission" do
    expect(xml).to include("2025-01-15")
  end

  it "contient la date d'échéance" do
    expect(xml).to include("2025-02-14")
  end

  it "contient le code devise EUR" do
    expect(xml).to include("EUR")
  end

  it "contient InvoiceTypeCode 380" do
    expect(xml).to include("380")
  end

  it "contient le nom du partenaire (acheteur)" do
    expect(xml).to include("Acme SA")
  end

  it "contient le numéro TVA du partenaire" do
    expect(xml).to include("BE0123456789")
  end

  it "contient le montant HT total" do
    expect(xml).to include("1000.00")
  end

  it "contient le montant TVA" do
    expect(xml).to include("210.00")
  end

  it "contient le montant TVAC" do
    expect(xml).to include("1210.00")
  end

  it "contient une ligne de facture" do
    expect(xml).to include("Prestation de service")
  end

  it "contient le taux TVA 21%" do
    expect(xml).to include("21")
  end

  it "produit du XML valide parsable par Nokogiri" do
    doc = Nokogiri::XML(xml)
    expect(doc.errors).to be_empty
  end
end
