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
      ubl = '<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" ' \
            'xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" ' \
            'xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">' \
            "<cbc:ID>IN-1</cbc:ID><cbc:IssueDate>2025-06-01</cbc:IssueDate>" \
            "<cac:AccountingSupplierParty><cac:Party><cac:PartyName><cbc:Name>Fournisseur</cbc:Name></cac:PartyName>" \
            "<cac:PartyTaxScheme><cbc:CompanyID>BE0123456789</cbc:CompanyID></cac:PartyTaxScheme></cac:Party></cac:AccountingSupplierParty>" \
            "<cac:LegalMonetaryTotal><cbc:TaxInclusiveAmount>605.00</cbc:TaxInclusiveAmount></cac:LegalMonetaryTotal></Invoice>"
      body = { event: "INVOICE_RECEIVED", receiver: "0208:0555666777", ubl_xml: ubl }.to_json

      expect {
        post_webhook(entity.peppol_webhook_token, body, "X-Peppol-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "s3cret", body))
      }.to change { Accounting::Invoice.where(external_ref: "IN-1").count }.by(1)
      expect(response).to have_http_status(:ok)
    end
  end
end
