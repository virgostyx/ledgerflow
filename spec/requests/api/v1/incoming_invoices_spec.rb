require 'rails_helper'

# A Peppol invoice received in LedgerFlow, taken over by a third party (BudgetFlow): its documents are downloaded, then it is
# claimed under the third party's own reference; its later PUT fills the same draft in (no second invoice).
RSpec.describe 'Api::V1::IncomingInvoices', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:purchase) { create(:journal, :purchase, default_account: account_440) }
  let!(:suspense) { create(:account, code: '499000', label_fr: "Comptes d'attente", account_class: 4, entity: entity) }
  let!(:supplier) { create(:partner, :with_vat, partner_type: :supplier, name: 'Fournisseur SA') } # BE0123456789
  let(:scopes)  { %w[invoices:read invoices:write partners:write] }
  let(:issued)  { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: scopes) }
  let(:headers) { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:pdf) { "%PDF-1.4\nbody\n%%EOF\n" }
  let(:xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
               xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
               xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        <cbc:ID>SUP-2026-001</cbc:ID><cbc:IssueDate>#{Date.current}</cbc:IssueDate><cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
        <cac:OrderReference><cbc:ID>PO-2026-014</cbc:ID></cac:OrderReference>
        <cac:AdditionalDocumentReference><cbc:ID>p</cbc:ID><cac:Attachment><cbc:EmbeddedDocumentBinaryObject mimeCode="application/pdf" filename="f.pdf">#{Base64.strict_encode64(pdf)}</cbc:EmbeddedDocumentBinaryObject></cac:Attachment></cac:AdditionalDocumentReference>
        <cac:AccountingSupplierParty><cac:Party><cac:PartyName><cbc:Name>Fournisseur SA</cbc:Name></cac:PartyName>
          <cac:PartyTaxScheme><cbc:CompanyID>BE0123456789</cbc:CompanyID></cac:PartyTaxScheme></cac:Party></cac:AccountingSupplierParty>
        <cac:LegalMonetaryTotal><cbc:TaxExclusiveAmount currencyID="EUR">100.00</cbc:TaxExclusiveAmount>
          <cbc:TaxInclusiveAmount currencyID="EUR">121.00</cbc:TaxInclusiveAmount></cac:LegalMonetaryTotal>
        <cac:TaxTotal><cbc:TaxAmount currencyID="EUR">21.00</cbc:TaxAmount></cac:TaxTotal>
      </Invoice>
    XML
  end
  let!(:received) { Peppol::ReceiveInvoice.call(xml: xml, fiscal_year: fiscal_year)[:invoice] }

  def json = JSON.parse(response.body)
  def claim(ref = 'bf-invoice-10', id: received.id) = post("/api/v1/incoming_invoices/#{id}/claim", params: { external_ref: ref }, headers: headers, as: :json)
  def export(ref = 'bf-invoice-10', price: '100.0')
    put "/api/v1/invoices/#{ref}", headers: headers, as: :json, params: {
      document_type: 'invoice', post: false, invoice_type: 'supplier', partner_external_ref: 'bf-supplier-5',
      supplier_reference: 'SUP-2026-001', invoice_date: Date.current.iso8601, currency: 'EUR', project_name: 'Water Access Zambia', budget_line: '3.2.1',
      lines: [ { description: 'Mission', quantity: '1.0', unit_price: price, vat_rate: '21.0' } ] }
  end
  before { create(:partner, :supplier, external_ref: 'bf-supplier-5', vat_number: nil) }

  describe 'GET documents' do
    it 'serves the PDF and the original XML' do
      get "/api/v1/incoming_invoices/#{received.id}/documents/pdf", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(pdf)
      expect(response.media_type).to eq('application/pdf')

      get "/api/v1/incoming_invoices/#{received.id}/documents/xml", headers: headers
      expect(response.body).to eq(xml)
    end

    it 'answers 404 for an unknown kind, a missing document, a typed invoice or another entity' do
      get "/api/v1/incoming_invoices/#{received.id}/documents/zip", headers: headers
      expect(response).to have_http_status(:not_found)

      received.pdf_document.purge
      get "/api/v1/incoming_invoices/#{received.id}/documents/pdf", headers: headers
      expect(response).to have_http_status(:not_found)

      typed = create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year)
      get "/api/v1/incoming_invoices/#{typed.id}/documents/xml", headers: headers
      expect(response).to have_http_status(:not_found)

      other = create(:entity, budgetflow_enabled: true)
      foreign = ActsAsTenant.with_tenant(other) do
        fy = create(:fiscal_year, entity: other)
        create(:invoice, :draft, invoice_type: :supplier, partner: create(:partner, :supplier), fiscal_year: fy)
          .tap { |i| i.ubl_document.attach(io: StringIO.new('<x/>'), filename: 'x.xml', content_type: 'application/xml') }
      end
      get "/api/v1/incoming_invoices/#{foreign.id}/documents/xml", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'requires the invoices:read scope' do
      issued.first.update!(scopes: %w[invoices:write])

      get "/api/v1/incoming_invoices/#{received.id}/documents/pdf", headers: headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST claim' do
    it 'makes the draft the third party\'s own: its reference, revision 1, still a draft with its documents' do
      claim

      expect(response).to have_http_status(:ok)
      expect(json).to include('id' => received.id, 'external_ref' => 'bf-invoice-10', 'status' => 'draft', 'supplier_reference' => 'SUP-2026-001')
      expect(received.reload).to have_attributes(external_ref: 'bf-invoice-10', revision: 1, status: 'draft', supplier_reference: 'SUP-2026-001')
      expect(Accounting::Invoice.external).to include(received)
      expect(received.ubl_document).to be_attached
      expect(received.pdf_document).to be_attached
    end

    it 'is idempotent for the same reference and refuses another one (409)' do
      claim
      claim
      expect(response).to have_http_status(:ok)

      claim('bf-invoice-99')
      expect(response).to have_http_status(:conflict)
      expect(received.reload.external_ref).to eq('bf-invoice-10')
    end

    it 'answers 422 without a reference, 404 for an unknown or non-Peppol invoice' do
      claim('')
      expect(response).to have_http_status(:unprocessable_content)

      claim(id: 0)
      expect(response).to have_http_status(:not_found)

      typed = create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year)
      claim(id: typed.id)
      expect(response).to have_http_status(:not_found)
    end

    it 'answers 409 once the accountant has posted or cancelled it' do
      received.update_columns(status: Accounting::Invoice.statuses[:cancelled])

      claim

      expect(response).to have_http_status(:conflict)
      expect(received.reload.external_ref).to eq('SUP-2026-001')
    end

    it 'answers 409 when the reference is already used by another document' do
      export('bf-invoice-10')

      claim('bf-invoice-10')

      expect(response).to have_http_status(:conflict)
    end

    it 'requires the invoices:write scope' do
      issued.first.update!(scopes: %w[invoices:read])

      claim

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'the export that follows the claim' do
    before { claim }

    it 'fills the same draft in (200, no second invoice), documents kept' do
      expect { export }.not_to change(Accounting::Invoice, :count)

      expect(response).to have_http_status(:ok)
      expect(json).to include('id' => received.id, 'revision' => 1, 'status' => 'draft')
      received.reload
      expect(received.lines.map { |l| [ l.description, l.account.code ] }).to eq([ [ 'Mission', '499000' ] ])
      expect(received).to have_attributes(external_project_name: 'Water Access Zambia', external_budget_line: '3.2.1',
                                          order_reference: 'PO-2026-014')
      expect(received.ubl_document).to be_attached
      expect(received.pdf_document).to be_attached
    end

    it 'is refused (409) once the accountant has worked on the draft meanwhile' do
      received.update!(description: 'Coded by the accountant')

      export

      expect(response).to have_http_status(:conflict)
      expect(json['errors']['base'].first).to match(/accountant/i)
    end
  end
end
