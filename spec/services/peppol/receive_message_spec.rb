require "rails_helper"

# F06 step 1 (docs/dev/features/F06-audit.md): nothing that reaches us through Peppol is lost. Every message is recorded first, with its XML,
# under its own identifier (a message delivered twice is one record); then it is worked on, and what cannot be worked on waits for a
# person ("needs_review", with the reasons) instead of vanishing.
RSpec.describe Peppol::ReceiveMessage do
  include_context "with_open_fiscal_year"
  include_context "with_suspense_account"

  let!(:supplier) { create(:partner, partner_type: :supplier, name: "Fournisseur SA", vat_number: PeppolUbl::SUPPLIER_VAT) }

  def ubl(number: "SUP-2026-001", root: "Invoice", vat: PeppolUbl::SUPPLIER_VAT, **options) = PeppolUbl.invoice(number: number, root: root, vat: vat, **options)

  def event(xml: ubl, message_id: "AP-MSG-1", **attrs) = Peppol::Event.new(kind: :received, message_id: message_id, receiver: "0208:0999999999", xml: xml, **attrs)
  def take_in(**attrs) = described_class.call(event: event(**attrs))
  def messages = Accounting::PeppolMessage.inbound

  describe "recording" do
    it "records the message first, with its identifier, parties, type, process and XML, and drafts the invoice" do
      result = take_in

      message = messages.sole
      expect(result[:message]).to eq(message)
      expect(message).to have_attributes(message_id: "AP-MSG-1", receiver_id: "0208:0999999999", sender_id: "0208:0123456749", document_type: "invoice",
                                         process: "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0", status: "processed", problems: [])
      expect(message.xml).to include("SUP-2026-001")
      expect(message.invoice).to be_draft
      expect(message.invoice.supplier_reference).to eq("SUP-2026-001")
    end

    it "recognises a credit note, and a document that is not an invoice" do
      credit = take_in(xml: ubl(root: "CreditNote", number: "CN-1"), message_id: "AP-MSG-2")[:message]
      order  = take_in(xml: ubl(root: "Order", number: "PO-1"), message_id: "AP-MSG-3")[:message]

      expect(credit).to have_attributes(document_type: "credit_note", status: "processed")
      expect(credit.invoice).to be_credit_note
      expect(order).to have_attributes(document_type: "other", status: "processed", invoice_id: nil)
      expect(order.note).to include("without an entry")
    end
  end

  describe "a message delivered twice" do
    it "is one record and one draft (idempotence by message id)" do
      first  = take_in
      second = take_in

      expect(messages.count).to eq(1)
      expect(Accounting::Invoice.supplier.count).to eq(1)
      expect(second[:duplicate]).to be(true)
      expect(second[:invoice]).to eq(first[:invoice])
    end

    it "is told apart by its content when the Access Point gives no identifier" do
      take_in(message_id: nil)
      take_in(message_id: nil)
      take_in(message_id: nil, xml: ubl(number: "SUP-2026-002"))

      expect(messages.count).to eq(2)
      expect(messages.pluck(:message_id)).to all(start_with("sha256:"))
    end

    it "keeps the record of a message that is retried while the first try is being worked on" do
      take_in
      allow(Accounting::PeppolMessage).to receive(:find_by).and_return(nil).once # the check misses: the unique key must answer

      expect { take_in }.not_to change(Accounting::PeppolMessage, :count)
    end
  end

  describe "what cannot be worked on is kept" do
    it "keeps a document the mapper cannot read, as needs_review with the reason, and no draft" do
      result = take_in(xml: "<Invoice><nothing/></Invoice>", message_id: "AP-BAD")

      expect(result).to be_success
      expect(messages.sole).to have_attributes(status: "needs_review", invoice_id: nil)
      expect(messages.sole.problems.join).to include("no number")
      expect(messages.sole.xml).to include("<nothing/>")
      expect(Accounting::Invoice.count).to eq(0)
    end

    it "keeps a message that is not even XML" do
      take_in(xml: "not xml at all", message_id: "AP-GARBAGE")

      expect(messages.sole).to have_attributes(status: "needs_review", document_type: "other")
      expect(messages.sole.xml).to eq("not xml at all")
    end

    it "keeps a message when the entity has no open fiscal year" do
      fiscal_year.update_columns(status: Accounting::FiscalYear.statuses[:closed])

      take_in

      expect(messages.sole).to have_attributes(status: "needs_review")
      expect(messages.sole.problems.join).to include("fiscal year")
    end

    it "never raises after the message is stored: an unexpected error is a reason to review" do
      allow(Peppol::ReceiveInvoice).to receive(:call).and_raise(RuntimeError, "boom")

      expect(take_in).to be_success
      expect(messages.sole).to have_attributes(status: "needs_review")
      expect(messages.sole.problems.join).to include("boom")
    end
  end

  describe "the document store (F03)" do
    it "keeps the XML there, linked to the message" do
      message = take_in[:message]

      expect(message.document).to have_attributes(origin: "peppol", content_type: "application/xml", kind: "purchase_invoice")
      expect(message.document.file.download).to eq(message.xml)
    end

    it "keeps the message even when the document store refuses the file, and says so" do
      allow(Accounting::UploadDocument).to receive(:call).and_return(LightService::Context.make(document: nil, reason: :scan_unavailable).tap { |c| c.fail!("virus scan unavailable") })

      message = take_in[:message]

      expect(message).to have_attributes(status: "processed", document_id: nil)
      expect(message.note).to include("document store")
    end
  end
end

RSpec.describe Peppol::HandleEvent, "a received document" do
  include_context "with_open_fiscal_year"
  include_context "with_suspense_account"

  it "is ignored, with a log line, when it is addressed to nobody we know" do
    expect(Rails.logger).to receive(:warn).with(/0208:0000000000/)

    result = ActsAsTenant.without_tenant { described_class.call(event: Peppol::Event.new(kind: :received, receiver: "0208:0000000000", xml: "<Invoice/>")) }

    expect(result[:ignored]).to be(true)
    expect(Accounting::PeppolMessage.count).to eq(0)
  end

  it "is recorded in the entity it is addressed to" do
    entity.update!(peppol_participant_id: "0208:0999999999")
    xml = Peppol::AccessPoint::Simulator.new(entity).send(:sample_invoice)

    ActsAsTenant.without_tenant { described_class.call(event: Peppol::Event.new(kind: :received, message_id: "M1", receiver: "0208:0999999999", xml: xml)) }

    expect(Accounting::PeppolMessage.inbound.sole).to have_attributes(entity_id: entity.id, status: "processed")
  end
end
