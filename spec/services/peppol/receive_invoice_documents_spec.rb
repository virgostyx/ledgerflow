require "rails_helper"

# What a received Peppol invoice keeps: the original UBL XML (the legal original), the PDF the supplier embedded in it, and the
# references that tie it to a purchase order and a project.
RSpec.describe Peppol::ReceiveInvoice, "documents and references" do
  include_context "with_open_fiscal_year"

  let!(:supplier) { create(:partner, :with_vat, partner_type: :supplier) } # BE0123456789
  let(:pdf) { "%PDF-1.4\n1 0 obj<< /Type /Catalog >>endobj\ntrailer<< /Root 1 0 R >>\n%%EOF\n" }

  def ubl(number: "SUP-2026-001", vat: "BE0123456789", references: true, attachments: "")
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
               xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
               xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        <cbc:ID>#{number}</cbc:ID>
        <cbc:IssueDate>2026-09-01</cbc:IssueDate>
        <cbc:DueDate>2026-10-01</cbc:DueDate>
        <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
        <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
        #{'<cbc:BuyerReference>PRJ-ZM-3.2.1</cbc:BuyerReference>' if references}
        #{'<cac:OrderReference><cbc:ID>PO-2026-014</cbc:ID></cac:OrderReference>' if references}
        #{attachments}
        <cac:AccountingSupplierParty><cac:Party>
          <cac:PartyName><cbc:Name>Fournisseur SA</cbc:Name></cac:PartyName>
          <cac:PartyTaxScheme><cbc:CompanyID>#{vat}</cbc:CompanyID><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme>
        </cac:Party></cac:AccountingSupplierParty>
        <cac:TaxTotal><cbc:TaxAmount currencyID="EUR">105.00</cbc:TaxAmount></cac:TaxTotal>
        <cac:LegalMonetaryTotal>
          <cbc:TaxExclusiveAmount currencyID="EUR">500.00</cbc:TaxExclusiveAmount>
          <cbc:TaxInclusiveAmount currencyID="EUR">605.00</cbc:TaxInclusiveAmount>
        </cac:LegalMonetaryTotal>
      </Invoice>
    XML
  end

  def embedded(content, mime: "application/pdf", filename: "SUP-2026-001.pdf")
    <<~XML
      <cac:AdditionalDocumentReference>
        <cbc:ID>invoice-pdf</cbc:ID>
        <cac:Attachment><cbc:EmbeddedDocumentBinaryObject mimeCode="#{mime}" filename="#{filename}">#{Base64.strict_encode64(content)}</cbc:EmbeddedDocumentBinaryObject></cac:Attachment>
      </cac:AdditionalDocumentReference>
    XML
  end

  def receive_xml(xml) = described_class.call(xml: xml, fiscal_year: fiscal_year)

  it "stores the order reference and the buyer reference" do
    invoice = receive_xml(ubl)[:invoice]

    expect(invoice).to have_attributes(order_reference: "PO-2026-014", buyer_reference: "PRJ-ZM-3.2.1")
  end

  it "leaves them empty when the supplier gave none" do
    invoice = receive_xml(ubl(references: false))[:invoice]

    expect(invoice).to have_attributes(order_reference: nil, buyer_reference: nil)
  end

  it "keeps the received XML, byte for byte, as the original document" do
    xml = ubl
    invoice = receive_xml(xml)[:invoice]

    expect(invoice.ubl_document).to be_attached
    expect(invoice.ubl_document.download).to eq(xml)
    expect(invoice.ubl_document).to have_attributes(filename: have_attributes(to_s: "SUP-2026-001.xml"), content_type: "application/xml")
  end

  it "extracts the PDF the supplier embedded in the XML" do
    invoice = receive_xml(ubl(attachments: embedded(pdf)))[:invoice]

    expect(invoice.pdf_document).to be_attached
    expect(invoice.pdf_document.download).to eq(pdf)
    expect(invoice.pdf_document).to have_attributes(filename: have_attributes(to_s: "SUP-2026-001.pdf"), content_type: "application/pdf")
  end

  it "has no PDF when the supplier embedded none, but still keeps the XML" do
    invoice = receive_xml(ubl)[:invoice]

    expect(invoice.pdf_document).not_to be_attached
    expect(invoice.ubl_document).to be_attached
  end

  it "ignores an embedded file that is not a PDF (the invoice is still received)" do
    result = receive_xml(ubl(attachments: embedded("<html>not a pdf</html>", mime: "application/pdf")))

    expect(result).to be_success
    expect(result[:invoice].pdf_document).not_to be_attached
    expect(result[:invoice].ubl_document).to be_attached
  end

  it "ignores other embedded types such as images" do
    invoice = receive_xml(ubl(attachments: embedded("\x89PNG", mime: "image/png", filename: "logo.png")))[:invoice]

    expect(invoice.pdf_document).not_to be_attached
  end

  it "does not create a second draft when the Access Point delivers the same document twice" do
    xml = ubl(attachments: embedded(pdf))
    first = receive_xml(xml)[:invoice]

    expect { @second = receive_xml(xml) }.not_to change(Accounting::Invoice, :count)

    expect(@second).to be_success
    expect(@second[:invoice]).to eq(first)
  end

  it "receives the same number from another supplier as a separate invoice" do
    create(:partner, partner_type: :supplier, vat_number: "BE0987654321")
    receive_xml(ubl)

    expect { receive_xml(ubl(vat: "BE0987654321")) }.to change(Accounting::Invoice, :count).by(1)
  end

  it "receives the same number again once the earlier invoice was cancelled" do
    receive_xml(ubl)[:invoice].update_columns(status: Accounting::Invoice.statuses[:cancelled])

    expect { receive_xml(ubl) }.to change(Accounting::Invoice, :count).by(1)
  end

  it "leaves no invoice behind when its documents cannot be stored" do
    allow_any_instance_of(ActiveStorage::Attached::One).to receive(:attach).and_raise(StandardError, "disk full")

    result = nil
    expect { result = receive_xml(ubl) }.not_to change(Accounting::Invoice, :count)

    expect(result).to be_failure
    expect(result.message).to include("disk full")
  end
end
