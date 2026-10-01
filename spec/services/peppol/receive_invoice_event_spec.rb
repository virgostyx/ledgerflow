require "rails_helper"

# A Peppol invoice received by an entity that uses BudgetFlow is announced to it through the event feed.
RSpec.describe Peppol::ReceiveInvoice, "the received event" do
  include_context "with_open_fiscal_year"
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:supplier) { create(:partner, :with_vat, partner_type: :supplier, name: "Fournisseur SA") } # BE0123456789
  let(:pdf) { "%PDF-1.4\nbody\n%%EOF\n" }

  def ubl(number: "SUP-2026-001", root: "Invoice", pdf: true)
    attachment = pdf ? "<cac:AdditionalDocumentReference><cbc:ID>p</cbc:ID><cac:Attachment><cbc:EmbeddedDocumentBinaryObject mimeCode=\"application/pdf\" filename=\"f.pdf\">#{Base64.strict_encode64(self.pdf)}</cbc:EmbeddedDocumentBinaryObject></cac:Attachment></cac:AdditionalDocumentReference>" : ""
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <#{root} xmlns="urn:oasis:names:specification:ubl:schema:xsd:#{root}-2"
               xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
               xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        <cbc:ID>#{number}</cbc:ID>
        <cbc:IssueDate>2026-09-01</cbc:IssueDate>
        <cbc:DueDate>2026-10-01</cbc:DueDate>
        <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
        <cbc:BuyerReference>PRJ-ZM</cbc:BuyerReference>
        <cac:OrderReference><cbc:ID>PO-2026-014</cbc:ID></cac:OrderReference>
        #{attachment}
        <cac:AccountingSupplierParty><cac:Party>
          <cac:PartyName><cbc:Name>Fournisseur SA</cbc:Name></cac:PartyName>
          <cac:PartyTaxScheme><cbc:CompanyID>BE0123456789</cbc:CompanyID><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme>
        </cac:Party></cac:AccountingSupplierParty>
        <cac:TaxTotal><cbc:TaxAmount currencyID="EUR">105.00</cbc:TaxAmount></cac:TaxTotal>
        <cac:LegalMonetaryTotal>
          <cbc:TaxExclusiveAmount currencyID="EUR">500.00</cbc:TaxExclusiveAmount>
          <cbc:TaxInclusiveAmount currencyID="EUR">605.00</cbc:TaxInclusiveAmount>
        </cac:LegalMonetaryTotal>
      </#{root}>
    XML
  end

  def receive_xml(xml) = described_class.call(xml: xml, fiscal_year: fiscal_year)
  def events = Accounting::InvoiceEvent.where(event_type: "received")

  it "records a received event with what the project manager needs to recognise and take the invoice" do
    invoice = receive_xml(ubl)[:invoice]

    expect(events.count).to eq(1)
    expect(events.first).to have_attributes(invoice_id: invoice.id, entity_id: entity.id)
    expect(events.first.payload).to include(
      "lf_id" => invoice.id, "supplier_reference" => "SUP-2026-001", "currency" => "EUR",
      "invoice_date" => "2026-09-01", "due_date" => "2026-10-01",
      "amount_excl_vat" => "500.0", "vat_amount" => "105.0", "total_incl_vat" => "605.0",
      "order_reference" => "PO-2026-014", "buyer_reference" => "PRJ-ZM", "has_pdf" => true,
      "supplier" => { "name" => "Fournisseur SA", "vat_number" => "BE0123456789" }
    )
  end

  it "says when there is no PDF to take" do
    receive_xml(ubl(pdf: false))

    expect(events.first.payload["has_pdf"]).to be false
  end

  it "does not announce the same document twice" do
    xml = ubl
    receive_xml(xml)

    expect { receive_xml(xml) }.not_to change { events.count }
  end

  it "does not announce a credit note (not handled by BudgetFlow yet)" do
    receive_xml(ubl(root: "CreditNote"))

    expect(events.count).to eq(0)
  end

  it "says nothing for an entity that does not use BudgetFlow" do
    entity.update_columns(budgetflow_enabled: false)

    receive_xml(ubl)

    expect(events.count).to eq(0)
  end

  it "leaves no event behind when the reception fails" do
    allow_any_instance_of(ActiveStorage::Attached::One).to receive(:attach).and_raise(StandardError, "disk full")

    receive_xml(ubl)

    expect(events.count).to eq(0)
  end
end
