require "rails_helper"

RSpec.describe "Peppol::Webhooks", type: :request do
  include_context "with_open_fiscal_year"

  let(:partner) { create(:partner, :with_vat) }
  let!(:invoice) do
    create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, peppol_id: "MSG-1", peppol_status: :queued)
  end

  def post_webhook(token, body, headers = {})
    post "/peppol/webhooks/#{token}", params: body, headers: { "Content-Type" => "application/json" }.merge(headers)
  end

  context "with an entity on the simulator" do
    let(:token) { entity.peppol_webhook_token }
    let(:body)  { { event: "delivered", message_id: "MSG-1" }.to_json }

    before { entity.update!(peppol_access_point: :simulator) }

    def signature(payload) = OpenSSL::HMAC.hexdigest("SHA256", entity.peppol_webhook_token, payload)

    it "applies the event to the invoice of that entity" do
      post_webhook(token, body, "X-Simulator-Signature" => signature(body))
      expect(response).to have_http_status(:ok)
      expect(invoice.reload.peppol_status).to eq("delivered")
    end

    it "rejects a bad signature" do
      post_webhook(token, body, "X-Simulator-Signature" => "nope")
      expect(response).to have_http_status(:unauthorized)
      expect(invoice.reload.peppol_status).to eq("queued")
    end

    it "rejects a missing signature" do
      post_webhook(token, body)
      expect(response).to have_http_status(:unauthorized)
    end

    it "answers 400 to a body that is not JSON" do
      bad = "{ invalid"
      post_webhook(token, bad, "X-Simulator-Signature" => signature(bad))
      expect(response).to have_http_status(:bad_request)
    end

    it "answers 404 to an unknown token" do
      post_webhook("unknown", body, "X-Simulator-Signature" => signature(body))
      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 when the entity has no Access Point" do
      entity.update!(peppol_access_point: nil)
      post_webhook(token, body, "X-Simulator-Signature" => signature(body))
      expect(response).to have_http_status(:not_found)
    end
  end

  # F06 step 1: nothing is lost, a refusal leaves a trace, an old signed call is not replayed
  context "recording and refusals" do
    let(:token) { entity.peppol_webhook_token }

    describe "with the simulator" do
      before { entity.update!(peppol_access_point: :simulator, peppol_participant_id: "0208:0555666777") }

      def signature(payload) = OpenSSL::HMAC.hexdigest("SHA256", entity.peppol_webhook_token, payload)

      it "keeps a refused call in the audit trail of the entity, with the reason and who called" do
        body = { event: "delivered", message_id: "MSG-1" }.to_json
        post_webhook(token, body, "X-Simulator-Signature" => "nope")

        log = Accounting::AuditLog.where(action: "peppol_webhook_rejected").sole
        expect(log).to have_attributes(entity_id: entity.id, auditable_type: "Entity", auditable_id: entity.id)
        expect(log.payload).to include("reason" => "Bad signature")
        expect(log.ip_address).to be_present
      end

      it "does not write to the audit trail for an unknown token" do
        post_webhook("unknown", "{}", "X-Simulator-Signature" => "nope")

        expect(Accounting::AuditLog.where(action: "peppol_webhook_rejected")).to be_empty
      end

      it "records a received document once, however many times the Access Point sends it" do
        xml = Peppol::AccessPoint::Simulator.new(entity).send(:sample_invoice)
        body = { event: "received", message_id: "AP-1", receiver: "0208:0555666777", xml: xml }.to_json

        2.times { post_webhook(token, body, "X-Simulator-Signature" => signature(body)) }

        expect(response).to have_http_status(:ok)
        expect(Accounting::PeppolMessage.inbound.count).to eq(1)
        expect(Accounting::Invoice.supplier.count).to eq(1)
      end

      it "answers 200 for a document it could not work on, which it keeps for review" do
        body = { event: "received", message_id: "AP-2", receiver: "0208:0555666777", xml: "<Invoice/>" }.to_json
        post_webhook(token, body, "X-Simulator-Signature" => signature(body))

        expect(response).to have_http_status(:ok)
        expect(Accounting::PeppolMessage.sole).to have_attributes(status: "needs_review", xml: "<Invoice/>")
      end

      it "does not answer 200 when the message itself cannot be recorded: the Access Point must send it again" do
        allow(Peppol::ReceiveMessage).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "the database is down")
        body = { event: "received", message_id: "AP-3", receiver: "0208:0555666777", xml: "<Invoice/>" }.to_json

        expect { post_webhook(token, body, "X-Simulator-Signature" => signature(body)) }.to raise_error(ActiveRecord::StatementInvalid)
      end
    end

    describe "with B2Brouter" do
      before { entity.update!(peppol_access_point: :b2brouter, peppol_credentials: { "api_key" => "k", "account_id" => "1", "webhook_secret" => "whsec" }) }

      def signed(body, t) = "t=#{t},s=#{OpenSSL::HMAC.hexdigest('SHA256', 'whsec', "#{t}.#{body}")}"

      let(:body) { { code: "issued_invoice.state_change", data: { invoice_id: "MSG-1", state: "registered" } }.to_json }

      it "accepts a fresh signed call" do
        post_webhook(token, body, "X-B2Brouter-Signature" => signed(body, Time.now.to_i))

        expect(response).to have_http_status(:ok)
        expect(invoice.reload.peppol_status).to eq("delivered")
      end

      it "refuses a correctly signed call that is too old (replay), and keeps the refusal" do
        post_webhook(token, body, "X-B2Brouter-Signature" => signed(body, 10.minutes.ago.to_i))

        expect(response).to have_http_status(:unauthorized)
        expect(invoice.reload.peppol_status).to eq("queued")
        expect(Accounting::AuditLog.where(action: "peppol_webhook_rejected").sole.payload).to include("reason" => "Stale timestamp")
      end

      it "refuses a call dated in the future just as well" do
        post_webhook(token, body, "X-B2Brouter-Signature" => signed(body, 10.minutes.from_now.to_i))

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  context "with an entity on Digiteal" do
    before { entity.update!(peppol_access_point: :digiteal, peppol_credentials: { "api_key" => "k", "webhook_secret" => "s3cret" }) }

    it "verifies the signature with the secret of that entity" do
      body = { event: "INVOICE_DELIVERED", document_id: "MSG-1", status: "FAILED", error: "refused" }.to_json
      post_webhook(entity.peppol_webhook_token, body,
                   "X-Peppol-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "s3cret", body))
      expect(invoice.reload.peppol_status).to eq("failed")
    end

    it "books a received invoice in the entity addressed, found from the receiver identifier" do
      entity.update!(peppol_participant_id: "0208:0555666777")
      ubl = PeppolUbl.invoice(number: "IN-1", issue: "2025-06-01", due: nil, lines: [ [ 500, "S", 21 ] ])
      body = { event: "INVOICE_RECEIVED", receiver: "0208:0555666777", ubl_xml: ubl }.to_json

      expect {
        post_webhook(entity.peppol_webhook_token, body, "X-Peppol-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "s3cret", body))
      }.to change { Accounting::Invoice.where(external_ref: "IN-1").count }.by(1)
      expect(response).to have_http_status(:ok)
    end
  end
end
