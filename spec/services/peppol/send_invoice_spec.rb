require "rails_helper"

RSpec.describe Peppol::SendInvoice do
  include_context "with_open_fiscal_year"
  include ActiveJob::TestHelper

  let(:partner) { create(:partner, :with_vat, name: "Client SA") } # BE0123456789 => 0208:0123456789
  let(:invoice) do
    inv = create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, invoice_number: "VTE2025/0001", invoice_date: Date.new(2025, 1, 15))
    create(:invoice_line, invoice: inv, account: create(:account, code: "700000"), description: "Service conseil", quantity: 1,
           unit_price: "1000.00", vat_rate: "21.00", position: 1)
    inv.compute_totals
    inv.save!
    inv
  end

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  before { entity.update!(peppol_access_point: :simulator, peppol_participant_id: "0208:0999999999") }

  context "with the simulator" do
    it "succeeds, keeps the message id of the Access Point and queues the invoice" do
      result = described_class.call(invoice: invoice)

      expect(result).to be_success
      expect(invoice.reload.peppol_id).to start_with("SIM-")
      expect(invoice.peppol_status).to eq("queued")
    end

    it "records that the invoice was sent, in its history" do
      described_class.call(invoice: invoice)
      expect(invoice.reload.peppol_events.sole).to have_attributes(kind: "sent", message: a_string_including(invoice.peppol_id))
    end

    it "ends up delivered once the Access Point confirms" do
      described_class.call(invoice: invoice)
      perform_enqueued_jobs

      expect(invoice.reload.peppol_status).to eq("delivered")
      expect(invoice.peppol_events.map(&:kind)).to contain_exactly("sent", "delivered")
    end

    it "ends up failed, with the reason, when the delivery fails" do
      partner.update!(peppol_participant_id: "9999:ABC-FAILED")
      described_class.call(invoice: invoice)
      perform_enqueued_jobs

      expect(invoice.reload.peppol_status).to eq("failed")
      expect(invoice.peppol_events.find_by(kind: :failed).message).to include("simulated")
    end

    it "can be sent again after a failure" do
      invoice.update!(peppol_status: :failed)
      expect(described_class.call(invoice: invoice)).to be_success
    end

    it "sends the credit note of an invoice too" do
      note = create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, document_type: :credit_note, credited_invoice: invoice,
                    invoice_number: "VTE2025/0002")
      create(:invoice_line, invoice: note, account: create(:account, code: "700100"), quantity: 1, unit_price: "100.00", vat_rate: "21.00", position: 1)

      expect(described_class.call(invoice: note)).to be_success
    end
  end

  context "with Digiteal (unvalidated adapter, stubbed)" do
    let(:endpoint) { %r{#{Regexp.escape(DIGITEAL_API_URL)}/api/invoices} }

    before do
      entity.update!(peppol_access_point: :digiteal, peppol_credentials: { "api_key" => "key-1", "webhook_secret" => "whsec-1" })
    end

    it "succeeds and keeps the id given by Digiteal" do
      stub_request(:post, endpoint).with(headers: { "Authorization" => "Bearer key-1" })
                                   .to_return(status: 201, body: { "id" => "PEPPOL-2025-001" }.to_json)

      expect(described_class.call(invoice: invoice)).to be_success
      expect(invoice.reload).to have_attributes(peppol_id: "PEPPOL-2025-001", peppol_status: "queued")
    end

    it "fails and keeps nothing when Digiteal refuses the document" do
      stub_request(:post, endpoint).to_return(status: 422, body: { "error" => "Invalid UBL" }.to_json)
      result = described_class.call(invoice: invoice)

      expect(result).to be_failure
      expect(result.message).to include("Digiteal")
      expect(invoice.reload.peppol_id).to be_nil
      expect(invoice.peppol_events).to be_empty
    end
  end

  context "when it cannot be sent" do
    def refused(result, matching)
      expect(result).to be_failure
      expect(result.message).to match(matching)
      expect(invoice.reload.peppol_id).to be_nil
    end

    it "refuses a draft" do
      draft = create(:invoice, :draft, partner: partner, fiscal_year: fiscal_year)
      expect(described_class.call(invoice: draft)).to be_failure
    end

    it "refuses a supplier invoice" do
      supplier_invoice = create(:invoice, :posted, :supplier, partner: partner, fiscal_year: fiscal_year)
      expect(described_class.call(invoice: supplier_invoice).message).to match(/customer/i)
    end

    it "refuses when the entity has no Access Point" do
      entity.update!(peppol_access_point: nil)
      refused(described_class.call(invoice: invoice), /Access Point/)
    end

    it "refuses when the entity has no Peppol identifier of its own" do
      entity.update!(peppol_participant_id: nil)
      refused(described_class.call(invoice: invoice), /your Peppol identifier/i)
    end

    it "refuses when the partner has no Peppol identifier and none can be derived" do
      partner.update!(vat_number: nil)
      refused(described_class.call(invoice: invoice), /Client SA/)
    end

    it "refuses a receiver that is not registered on the network" do
      partner.update!(peppol_participant_id: "9999:ABC-UNREGISTERED")
      refused(described_class.call(invoice: invoice), /not registered/)
    end

    it "refuses an invoice that is already queued or delivered" do
      invoice.update!(peppol_status: :delivered)
      expect(described_class.call(invoice: invoice).message).to match(/already/i)

      invoice.update!(peppol_status: :queued)
      expect(described_class.call(invoice: invoice).message).to match(/already/i)
    end

    it "fails cleanly on an unexpected error, changing nothing" do
      allow(ApplicationRecord).to receive(:transaction).and_raise(RuntimeError, "unexpected error")

      expect(described_class.call(invoice: invoice)).to be_failure
      expect(invoice.reload.peppol_id).to be_nil
    end
  end
end
