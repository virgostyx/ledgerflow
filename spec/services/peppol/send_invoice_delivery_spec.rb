require "rails_helper"

# F06 step 5, sending (docs/dev/features/spec.md §9, "Émission"): the PDF attached, a document that breaks a rule never sent, three attempts with a
# longer wait after a technical error (a refusal is not retried), the XML sent and the acknowledgement kept.
RSpec.describe Peppol::SendInvoice, "delivery" do
  include_context "with_open_fiscal_year"
  include ActiveJob::TestHelper

  let(:partner) { create(:partner, :with_vat, name: "Client SA") }
  let(:invoice) do
    inv = create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, invoice_number: "VTE2025/0001", invoice_date: Date.new(2025, 1, 15), due_date: Date.new(2025, 2, 15))
    create(:invoice_line, invoice: inv, account: create(:account, code: "700000"), description: "Service conseil", quantity: 1, unit_price: "1000.00", vat_rate: "21.00", position: 1)
    inv.compute_totals
    inv.save!
    inv
  end
  let(:access_point) { Peppol::AccessPoint::Simulator.new(entity) }

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  before do
    entity.update!(peppol_access_point: :simulator, peppol_participant_id: "0208:0999999922", vat_number: "BE0999999922", legal_name: "Ma Société SRL",
                   address_line1: "Rue 1", city: "Bruxelles", zip_code: "1000", country: "BE")
    allow(access_point).to receive(:registered?).and_return(true)
    allow(Peppol::AccessPoint).to receive(:for).and_return(access_point)
  end

  describe "the document sent" do
    before { allow(access_point).to receive(:send_document).and_return("AP-1") }

    it "carries the PDF of the invoice, which is a real PDF" do
      described_class.call(invoice: invoice)

      doc = Nokogiri::XML(Accounting::PeppolMessage.outbound.sole.xml)
      doc.remove_namespaces!
      node = doc.at_xpath("//AdditionalDocumentReference/Attachment/EmbeddedDocumentBinaryObject")
      expect(node["mimeCode"]).to eq("application/pdf")
      expect(Base64.decode64(node.text)).to start_with("%PDF")
      expect(node["filename"]).to eq("VTE2025_0001.pdf")
    end

    it "keeps the XML sent in the document store, linked to the invoice" do
      described_class.call(invoice: invoice)

      message = Accounting::PeppolMessage.outbound.sole
      expect(message.document).to have_attributes(origin: "peppol", kind: "sales_invoice", content_type: "application/xml")
      expect(message.document.links.map(&:target)).to eq([ invoice ])
    end

    it "keeps the acknowledgement of the Access Point once it confirms the delivery" do
      described_class.call(invoice: invoice)
      payload = { code: "issued_invoice.state_change", data: { invoice_id: "AP-1", state: "registered" } }.to_json

      ActsAsTenant.without_tenant { Peppol::HandleEvent.call(event: Peppol::Event.new(kind: :delivered, message_id: "AP-1", raw: payload)) }

      expect(Accounting::PeppolMessage.outbound.sole).to have_attributes(status: "delivered", ack: payload)
    end
  end

  describe "a document that breaks a rule" do
    it "is not sent, and the rules it breaks are told" do
      entity.update!(vat_number: "BE0999999999") # the check digits are wrong
      expect(access_point).not_to receive(:send_document)

      result = described_class.call(invoice: invoice)

      expect(result).to be_failure
      expect(result.message).to include("does not pass the checks").and include("BE0999999999")
      expect(Accounting::PeppolMessage.count).to eq(0)
      expect(invoice.reload.peppol_status).to eq("not_sent")
    end
  end

  describe "a technical error" do
    let(:down) { Peppol::AccessPoint::TemporaryError.new("B2Brouter cannot be reached") }

    it "does not fail: the message waits and the sending is tried again in a minute" do
      allow(access_point).to receive(:send_document).and_raise(down)

      result = described_class.call(invoice: invoice)

      expect(result).to be_success
      expect(result[:retrying]).to be(true)
      expect(invoice.reload.peppol_status).to eq("not_sent")
      expect(Accounting::PeppolMessage.outbound.sole).to have_attributes(status: "retrying", attempts: 1, problems: [ "B2Brouter cannot be reached" ], invoice_id: invoice.id)
      expect(Peppol::SendRetryJob).to have_been_enqueued.with(Accounting::PeppolMessage.outbound.sole.id, entity.id).at(be_within(5.seconds).of(1.minute.from_now))
    end

    it "does not let the same invoice be sent again meanwhile" do
      allow(access_point).to receive(:send_document).and_raise(down)
      described_class.call(invoice: invoice)

      expect(described_class.call(invoice: invoice).message).to include("waiting to be sent again")
    end

    describe "the retries" do
      let!(:message) do
        allow(access_point).to receive(:send_document).and_raise(down)
        described_class.call(invoice: invoice)
        clear_enqueued_jobs
        Accounting::PeppolMessage.outbound.sole
      end

      def retry_job = Peppol::SendRetryJob.perform_now(message.id, entity.id)

      it "gets through at the second attempt: the message becomes the sent one, and the invoice is queued" do
        allow(access_point).to receive(:send_document).and_return("AP-2")

        retry_job

        expect(message.reload).to have_attributes(status: "queued", message_id: "AP-2", problems: [], next_attempt_at: nil)
        expect(message.xml).to include("VTE2025/0001")
        expect(invoice.reload).to have_attributes(peppol_id: "AP-2", peppol_status: "queued")
        expect(invoice.peppol_events.sole.kind).to eq("sent")
        expect(message.document).to be_present
      end

      it "tries a third time after five minutes, and gives up there, saying so" do
        retry_job
        expect(message.reload).to have_attributes(status: "retrying", attempts: 2)
        expect(Peppol::SendRetryJob).to have_been_enqueued.at(be_within(5.seconds).of(5.minutes.from_now))

        clear_enqueued_jobs
        retry_job
        expect(message.reload).to have_attributes(status: "failed", next_attempt_at: nil)
        expect(message.problems.join).to include("cannot be reached").and include("3 attempts")
        expect(invoice.reload.peppol_status).to eq("failed")
        expect(invoice.peppol_events.first).to have_attributes(kind: "failed")
        expect(Peppol::SendRetryJob).not_to have_been_enqueued
      end

      it "does not retry a refusal of the document: it fails at once" do
        allow(access_point).to receive(:send_document).and_raise(Peppol::AccessPoint::Error, "B2Brouter: invalid document")

        retry_job

        expect(message.reload).to have_attributes(status: "failed", problems: [ "B2Brouter: invalid document" ])
        expect(invoice.reload.peppol_status).to eq("failed")
        expect(Peppol::SendRetryJob).not_to have_been_enqueued
      end

      it "does nothing for a message that is no longer waiting" do
        message.update!(status: :failed)
        expect(access_point).not_to receive(:send_document)

        retry_job
      end

      it "can be sent again by a person after it failed, as any failed invoice" do
        message.update!(status: :failed)
        invoice.update!(peppol_status: :failed)
        allow(access_point).to receive(:send_document).and_return("AP-3")

        expect(described_class.call(invoice: invoice)).to be_success
        expect(invoice.reload.peppol_id).to eq("AP-3")
      end
    end
  end

  describe "a refusal of the document" do
    it "fails at once, as before, with nothing kept" do
      allow(access_point).to receive(:send_document).and_raise(Peppol::AccessPoint::Error, "B2Brouter: invalid document")

      result = described_class.call(invoice: invoice)

      expect(result).to be_failure
      expect(Accounting::PeppolMessage.count).to eq(0)
      expect(Peppol::SendRetryJob).not_to have_been_enqueued
    end
  end
end
