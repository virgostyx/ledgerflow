require "rails_helper"

RSpec.describe "Peppol::Webhooks", type: :request do
  include_context "with_open_fiscal_year"

  def hmac_signature(body)
    OpenSSL::HMAC.hexdigest("SHA256", DIGITEAL_HMAC_SECRET, body)
  end

  describe "POST /peppol/webhooks" do
    context "delivery_confirmed — signature HMAC valide" do
      let(:partner) { create(:partner, :with_vat) }
      let!(:invoice) do
        create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year,
               peppol_id: "PEPPOL-2025-001", peppol_status: :queued)
      end

      let(:payload) do
        {
          event: "INVOICE_DELIVERED",
          document_id: "PEPPOL-2025-001",
          status: "DELIVERED"
        }.to_json
      end

      it "retourne 200" do
        post "/peppol/webhooks",
             params: payload,
             headers: {
               "Content-Type"       => "application/json",
               "X-Peppol-Signature" => hmac_signature(payload)
             }
        expect(response).to have_http_status(:ok)
      end

      it "met à jour peppol_status à delivered" do
        post "/peppol/webhooks",
             params: payload,
             headers: {
               "Content-Type"       => "application/json",
               "X-Peppol-Signature" => hmac_signature(payload)
             }
        expect(invoice.reload.peppol_status).to eq("delivered")
      end
    end

    context "invoice_received — nouvelle facture fournisseur entrante" do
      let(:partner) { create(:partner, :with_vat, partner_type: :supplier) }
      let(:ubl_xml) do
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
                   xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
                   xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
            <cbc:ID>INCOMING-001</cbc:ID>
            <cbc:IssueDate>2025-06-01</cbc:IssueDate>
            <cbc:DueDate>2025-07-01</cbc:DueDate>
            <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
            <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
            <cac:AccountingSupplierParty>
              <cac:Party>
                <cac:PartyName><cbc:Name>Fournisseur Externe</cbc:Name></cac:PartyName>
                <cac:PartyTaxScheme>
                  <cbc:CompanyID>BE0123456789</cbc:CompanyID>
                  <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>
                </cac:PartyTaxScheme>
              </cac:Party>
            </cac:AccountingSupplierParty>
            <cac:LegalMonetaryTotal>
              <cbc:TaxExclusiveAmount currencyID="EUR">500.00</cbc:TaxExclusiveAmount>
              <cbc:TaxInclusiveAmount currencyID="EUR">605.00</cbc:TaxInclusiveAmount>
              <cbc:PayableAmount currencyID="EUR">605.00</cbc:PayableAmount>
            </cac:LegalMonetaryTotal>
            <cac:TaxTotal>
              <cbc:TaxAmount currencyID="EUR">105.00</cbc:TaxAmount>
            </cac:TaxTotal>
          </Invoice>
        XML
      end

      let(:payload) do
        {
          event: "INVOICE_RECEIVED",
          ubl_xml: ubl_xml
        }.to_json
      end

      it "retourne 200" do
        post "/peppol/webhooks",
             params: payload,
             headers: {
               "Content-Type"       => "application/json",
               "X-Peppol-Signature" => hmac_signature(payload)
             }
        expect(response).to have_http_status(:ok)
      end

      it "crée une facture fournisseur" do
        expect {
          post "/peppol/webhooks",
               params: payload,
               headers: {
                 "Content-Type"       => "application/json",
                 "X-Peppol-Signature" => hmac_signature(payload)
               }
        }.to change(Accounting::Invoice, :count).by(1)
      end
    end

    context "INVOICE_DELIVERED avec statut FAILED" do
      let(:partner) { create(:partner, :with_vat) }
      let!(:invoice) do
        create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year,
               peppol_id: "PEPPOL-2025-002", peppol_status: :queued)
      end

      let(:payload) do
        {
          event: "INVOICE_DELIVERED",
          document_id: "PEPPOL-2025-002",
          status: "FAILED"
        }.to_json
      end

      it "met à jour peppol_status à failed" do
        post "/peppol/webhooks",
             params: payload,
             headers: {
               "Content-Type"       => "application/json",
               "X-Peppol-Signature" => hmac_signature(payload)
             }
        expect(invoice.reload.peppol_status).to eq("failed")
      end
    end

    context "corps JSON invalide" do
      let(:malformed) { "{ invalid json" }

      it "retourne 400" do
        post "/peppol/webhooks",
             params: malformed,
             headers: {
               "Content-Type"       => "application/json",
               "X-Peppol-Signature" => hmac_signature(malformed)
             }
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "signature HMAC invalide" do
      let(:payload) { { event: "INVOICE_DELIVERED", document_id: "X" }.to_json }

      it "retourne 401" do
        post "/peppol/webhooks",
             params: payload,
             headers: {
               "Content-Type"       => "application/json",
               "X-Peppol-Signature" => "invalide"
             }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "sans signature" do
      let(:payload) { { event: "INVOICE_DELIVERED" }.to_json }

      it "retourne 401" do
        post "/peppol/webhooks",
             params: payload,
             headers: { "Content-Type" => "application/json" }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
