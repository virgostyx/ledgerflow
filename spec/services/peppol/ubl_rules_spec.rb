require "rails_helper"

# F06 step 5: what is checked of the UBL we send, offline. Not the official Schematron (see Peppol::UblRules): a subset, written by hand.
RSpec.describe Peppol::UblRules do
  include_context "with_open_fiscal_year"

  let(:partner) { create(:partner, :with_vat, name: "Client SA") }
  let(:invoice) do
    inv = create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, invoice_number: "VTE2025/0001", invoice_date: Date.new(2025, 1, 15), due_date: Date.new(2025, 2, 15))
    create(:invoice_line, invoice: inv, account: create(:account, code: "700000"), description: "Service conseil", quantity: 1, unit_price: "1000.00", vat_rate: "21.00", position: 1)
    inv.compute_totals
    inv.save!
    inv
  end

  before { entity.update!(peppol_access_point: :simulator, peppol_participant_id: "0208:0999999922", vat_number: "BE0999999922", legal_name: "Ma Société SRL", address_line1: "Rue 1", city: "Bruxelles", zip_code: "1000", country: "BE") }

  def built = Peppol::UblInvoiceBuilder.new(invoice).build
  def problems(xml = built) = described_class.call(xml)

  it "finds nothing wrong with the document the application builds for an ordinary invoice" do
    expect(problems).to eq([])
  end

  it "finds nothing wrong with its credit note" do
    note = create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, document_type: :credit_note, credited_invoice: invoice, invoice_number: "VTE2025/0002")
    create(:invoice_line, invoice: note, account: create(:account, code: "700100"), quantity: 1, unit_price: "100.00", vat_rate: "21.00", position: 1)
    note.compute_totals
    note.save!

    expect(problems(Peppol::UblInvoiceBuilder.new(note).build)).to eq([])
  end

  it "finds nothing wrong with an exempt or reverse-charge invoice, whose reason the application writes" do
    invoice.update_columns(vat_treatment: Accounting::Invoice.vat_treatments[:intracom_goods])
    partner.update!(country: "FR", vat_number: "FR12345678901", peppol_participant_id: "9957:FR12345678901")
    invoice.lines.each { |l| l.update_columns(vat_rate: 0, vat_amount: 0, total_incl_vat: l.subtotal_excl_vat) }
    invoice.reload.compute_totals
    invoice.save!

    expect(problems).to eq([])
  end

  describe "what it refuses" do
    def without(tag_path, xml = built)
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!
      doc.at_xpath(tag_path)&.remove
      doc.to_xml
    end

    it "a document that is not UBL" do
      expect(problems("not xml").join).to include("not valid UBL")
    end

    it "the wrong customization or profile (PEPPOL-R001, R003)" do
      xml = built.sub(Peppol::UblInvoiceBuilder::CUSTOMIZATION_ID, "urn:other").sub(Peppol::UblInvoiceBuilder::PROFILE_ID, "urn:other")

      expect(problems(xml).join).to include("PEPPOL-R001").and include("PEPPOL-R003")
    end

    it "a seller or a buyer with no name, no country, no endpoint (BR-06 to BR-11, PEPPOL-R010, R020)" do
      xml = without("/*/AccountingSupplierParty/Party/PartyLegalEntity/RegistrationName", without("/*/AccountingSupplierParty/Party/PartyName", built))
      xml = without("/*/AccountingCustomerParty/Party/PostalAddress/Country", xml)
      xml = without("/*/AccountingCustomerParty/Party/EndpointID", xml)

      expect(problems(xml).join).to include("BR-06").and include("BR-11").and include("PEPPOL-R010")
    end

    it "a line with no item name (BR-25)" do
      expect(problems(without("/*/InvoiceLine/Item/Name")).join).to include("BR-25")
    end

    it "a line with a negative price (BR-27)" do
      xml = built.sub(%r{(<cbc:PriceAmount[^>]*>)1000.00}, '\\1-1000.00')

      expect(problems(xml).join).to include("BR-27")
    end

    it "standard-rate VAT without the VAT number of the seller (BR-S-02)" do
      expect(problems(without("/*/AccountingSupplierParty/Party/PartyTaxScheme")).join).to include("BR-S-02")
    end

    it "an exemption without its reason (BR-E-10, BR-AE-10…)" do
      invoice.update_columns(vat_treatment: Accounting::Invoice.vat_treatments[:exempt])
      invoice.lines.each { |l| l.update_columns(vat_rate: 0, vat_amount: 0, total_incl_vat: l.subtotal_excl_vat) }
      invoice.reload.compute_totals
      invoice.save!

      expect(problems(without("/*/TaxTotal/TaxSubtotal/TaxCategory/TaxExemptionReason")).join).to include("BR-E-10")
    end

    it "an amount to pay with neither a due date nor payment terms (BR-CO-25)" do
      expect(problems(without("/*/DueDate")).join).to include("BR-CO-25")
    end

    it "figures that do not add up (the checks of a received invoice apply to what is sent)" do
      xml = built.sub(%r{(<cbc:TaxInclusiveAmount[^>]*>)1210.00}, '\\11300.00')

      expect(problems(xml).join).to include("TaxInclusiveAmount")
    end

    it "an invalid VAT number of the seller" do
      entity.update!(vat_number: "BE0999999999")

      expect(problems.join).to include("BE0999999999")
    end
  end
end
