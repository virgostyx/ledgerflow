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

  describe "les parties, le paiement et les catégories de TVA" do
    let(:doc) { Nokogiri::XML(xml).tap(&:remove_namespaces!) }
    let(:supplier) { "//AccountingSupplierParty/Party" }
    let(:customer) { "//AccountingCustomerParty/Party" }

    before do
      entity.update!(legal_name: "Ma Société SRL", vat_number: "BE0999999999", peppol_participant_id: "0208:0999999999",
                     address_line1: "Rue du Test 1", city: "Namur", zip_code: "5000")
      partner.update!(street: "Avenue Client 2", city: "Liège", zip: "4000", peppol_participant_id: nil)
    end

    it "prend l'émetteur dans l'entité, pas dans des constantes" do
      expect(doc.at_xpath("#{supplier}/PartyLegalEntity/RegistrationName").text).to eq("Ma Société SRL")
      expect(doc.at_xpath("#{supplier}/PartyTaxScheme/CompanyID").text).to eq("BE0999999999")
      expect(xml).not_to include("LedgerFlow ASBL")
    end

    it "indique l'EndpointID des deux parties avec leur schéma" do
      expect(doc.at_xpath("#{supplier}/EndpointID")).to have_attributes(text: "0999999999")
      expect(doc.at_xpath("#{supplier}/EndpointID")["schemeID"]).to eq("0208")
      expect(doc.at_xpath("#{customer}/EndpointID").text).to eq("0123456789") # dérivé de la TVA belge du partenaire
      expect(doc.at_xpath("#{customer}/EndpointID")["schemeID"]).to eq("0208")
    end

    it "utilise l'identifiant Peppol saisi sur le partenaire quand il existe" do
      partner.update!(peppol_participant_id: "9925:BE0555666777")
      expect(doc.at_xpath("#{customer}/EndpointID").text).to eq("BE0555666777")
      expect(doc.at_xpath("#{customer}/EndpointID")["schemeID"]).to eq("9925")
    end

    it "donne l'adresse postale complète des deux parties" do
      expect(doc.at_xpath("#{supplier}/PostalAddress/StreetName").text).to eq("Rue du Test 1")
      expect(doc.at_xpath("#{supplier}/PostalAddress/CityName").text).to eq("Namur")
      expect(doc.at_xpath("#{supplier}/PostalAddress/PostalZone").text).to eq("5000")
      expect(doc.at_xpath("#{customer}/PostalAddress/StreetName").text).to eq("Avenue Client 2")
      expect(doc.at_xpath("#{customer}/PostalAddress/CityName").text).to eq("Liège")
    end

    it "porte la référence de l'acheteur (référence externe, sinon numéro de facture)" do
      expect(doc.at_xpath("/Invoice/BuyerReference").text).to eq("VTE2025/0001")
      invoice.update!(external_ref: "PO-77")
      expect(Nokogiri::XML(described_class.new(invoice).build).tap(&:remove_namespaces!).at_xpath("/Invoice/BuyerReference").text).to eq("PO-77")
    end

    it "indique le moyen de paiement avec l'IBAN du premier compte bancaire actif" do
      bank = create(:bank_account)
      expect(doc.at_xpath("//PaymentMeans/PaymentMeansCode").text).to eq("30")
      expect(doc.at_xpath("//PaymentMeans/PayeeFinancialAccount/ID").text).to eq(bank.iban)
    end

    it "omet le moyen de paiement sans compte bancaire" do
      expect(doc.at_xpath("//PaymentMeans")).to be_nil
    end

    it "classe une vente belge à 21 % en catégorie S" do
      expect(doc.at_xpath("//TaxSubtotal/TaxCategory/ID").text).to eq("S")
      expect(doc.at_xpath("//TaxSubtotal/TaxCategory/TaxExemptionReason")).to be_nil
    end

    {
      "intracom_goods"              => %w[K Intra-community],
      "intracom_services"           => %w[AE reverse],
      "construction_reverse_charge" => %w[AE reverse],
      "export"                      => %w[G Export],
      "exempt"                      => %w[E exempt]
    }.each do |treatment, (category, reason)|
      it "classe #{treatment} en catégorie #{category}, à 0 %, avec le motif" do
        invoice.update_columns(vat_treatment: Accounting::Invoice.vat_treatments.fetch(treatment))
        invoice.lines.each { |l| l.update_columns(vat_rate: 0) }
        d = Nokogiri::XML(described_class.new(invoice.reload).build).tap(&:remove_namespaces!)

        expect(d.at_xpath("//TaxSubtotal/TaxCategory/ID").text).to eq(category)
        expect(d.at_xpath("//TaxSubtotal/TaxCategory/Percent").text.to_f).to eq(0)
        expect(d.at_xpath("//TaxSubtotal/TaxCategory/TaxExemptionReason").text).to include(reason)
        expect(d.at_xpath("//InvoiceLine/Item/ClassifiedTaxCategory/ID").text).to eq(category)
      end
    end

    it "classe en exonéré (E) une franchise de TVA, avec son motif" do
      entity.update!(vat_regime: :franchise)
      invoice.lines.each { |l| l.update_columns(vat_rate: 0) }
      d = Nokogiri::XML(described_class.new(invoice.reload).build).tap(&:remove_namespaces!)

      expect(d.at_xpath("//TaxSubtotal/TaxCategory/ID").text).to eq("E")
      expect(d.at_xpath("//TaxSubtotal/TaxCategory/TaxExemptionReason").text).to include("small business")
    end

    it "classe en Z une vente belge à 0 %" do
      invoice.lines.each { |l| l.update_columns(vat_rate: 0) }
      d = Nokogiri::XML(described_class.new(invoice.reload).build).tap(&:remove_namespaces!)
      expect(d.at_xpath("//TaxSubtotal/TaxCategory/ID").text).to eq("Z")
    end
  end

  describe "pour une note de crédit" do
    let(:credit_note) do
      create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, invoice_number: "VTE2025/0002",
             invoice_date: Date.new(2025, 1, 20), currency: "EUR",
             document_type: :credit_note, credited_invoice: invoice)
    end

    before do
      create(:invoice_line, invoice: credit_note, account: Accounting::Account.find_by!(code: "700000"),
             description: "Remise", quantity: 1, unit_price: "100.00", vat_rate: "21.00", position: 1)
      credit_note.compute_totals
      credit_note.save!
    end

    subject(:credit_xml) { described_class.new(credit_note).build }
    let(:doc) { Nokogiri::XML(credit_xml).tap(&:remove_namespaces!) }

    it "a la racine CreditNote dans le namespace CreditNote-2" do
      expect(doc.root.name).to eq("CreditNote")
      expect(credit_xml).to include("urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2")
    end

    it "porte le code de type 381" do
      expect(doc.at_xpath("//CreditNoteTypeCode").text).to eq("381")
      expect(doc.at_xpath("//InvoiceTypeCode")).to be_nil
    end

    it "référence la facture créditée" do
      expect(doc.at_xpath("//BillingReference/InvoiceDocumentReference/ID").text).to eq("VTE2025/0001")
    end

    it "utilise CreditNoteLine et CreditedQuantity" do
      expect(doc.at_xpath("//CreditNoteLine/CreditedQuantity").text).to eq("1.0")
      expect(doc.at_xpath("//InvoiceLine")).to be_nil
    end
  end
end
