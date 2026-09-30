require 'rails_helper'

# Third-party invoice injection (docs/dev/api/inbound-api.md): idempotent upsert keyed by external_ref,
# revisions by reversal + new document, cancellation with a reason.
RSpec.describe 'Api::V1::Invoices upsert/cancel/show', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) } # the API only exists for entities that declared BudgetFlow

  let!(:journal)  { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'BF-P-1') }
  let(:scopes)    { %w[invoices:read invoices:write] }
  let(:issued)    { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: scopes) }
  let(:headers)   { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:line)      { { account_code: '604000', description: 'Consulting', quantity: '2', unit_price: '50.00', vat_rate: '21' } }
  let(:payload) do
    { partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s,
      description: 'Mission', project_id: 7, lines: [ line ] }
  end

  def put_invoice(ref = 'BF-I-1', body = payload) = put("/api/v1/invoices/#{ref}", params: body, headers: headers, as: :json)
  def json = JSON.parse(response.body)
  def invoices(ref = 'BF-I-1') = Accounting::Invoice.external.where(external_ref: ref).order(:revision)

  describe 'PUT' do
    it 'creates, posts and books the invoice' do
      expect { put_invoice }.to change(Accounting::Invoice, :count).by(1)

      expect(response).to have_http_status(:created)
      invoice = invoices.first
      expect(invoice).to have_attributes(status: 'posted', revision: 1, project_id: 7, partner_id: supplier.id,
                                         subtotal_excl_vat: BigDecimal('100'), total_incl_vat: BigDecimal('121'))
      expect(invoice.journal_entry).to be_posted
      expect(json).to include('external_ref' => 'BF-I-1', 'status' => 'posted', 'revision' => 1,
                              'invoice_number' => invoice.invoice_number, 'total_incl_vat' => '121.0')
    end

    it 'accepts JSON numbers without going through Float' do
      line.merge!(quantity: 3, unit_price: 0.1, vat_rate: 0)
      put_invoice

      expect(invoices.first.subtotal_excl_vat).to eq(BigDecimal('0.3'))
    end

    it 'is idempotent: an identical replay changes nothing' do
      put_invoice
      counts = [ Accounting::Invoice.count, Accounting::JournalEntry.count ]

      put_invoice

      expect([ Accounting::Invoice.count, Accounting::JournalEntry.count ]).to eq(counts)

      expect(response).to have_http_status(:ok)
      expect(invoices.first.revision).to eq(1)
    end

    it 'revises: reverses the old document and posts revision 2 under the same external_ref' do
      put_invoice
      first = invoices.first
      line[:unit_price] = '60.00'

      put_invoice

      expect(response).to have_http_status(:ok)
      expect(first.reload).to be_cancelled
      expect(first.journal_entry.reload).to be_reversed
      expect(invoices.map(&:revision)).to eq([ 1, 2 ])
      expect(invoices.last).to have_attributes(status: 'posted', total_incl_vat: BigDecimal('145.2'))
      expect(json['revision']).to eq(2)
    end

    it 'refuses a revision with 409 when the current document is paid, and leaves everything untouched' do
      put_invoice
      invoices.first.update_columns(status: Accounting::Invoice.statuses[:paid])
      line[:unit_price] = '60.00'

      expect { put_invoice }.not_to change(Accounting::Invoice, :count)

      expect(response).to have_http_status(:conflict)
      expect(invoices.first).to be_paid
    end

    it 'posts a new revision when the previous one was cancelled by the third party' do
      put_invoice
      delete '/api/v1/invoices/BF-I-1', params: { reason: 'Mistake' }, headers: headers, as: :json

      put_invoice

      expect(response).to have_http_status(:created)
      expect(invoices.map(&:status)).to eq(%w[cancelled posted])
      expect(invoices.last.revision).to eq(2)
    end

    it 'answers 422 for an unknown partner' do
      put_invoice('BF-I-1', payload.merge(partner_external_ref: 'NOPE'))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['partner_external_ref']).to be_present
    end

    it 'answers 422 naming the line for an unknown account code' do
      line[:account_code] = '999999'

      put_invoice

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['errors']['lines[0].account_code']).to be_present
      expect(Accounting::Invoice.count).to eq(0)
    end

    it 'answers 422 for missing lines, a bad amount or an unknown invoice_type' do
      put_invoice('A', payload.merge(lines: []))
      expect(response).to have_http_status(:unprocessable_content)

      line[:unit_price] = 'abc'
      put_invoice('B')
      expect(response).to have_http_status(:unprocessable_content)

      line[:unit_price] = '10'
      put_invoice('C', payload.merge(invoice_type: 'alien'))
      expect(response).to have_http_status(:unprocessable_content)
      expect(Accounting::Invoice.count).to eq(0)
    end

    it 'answers 409 when no open fiscal year covers the date' do
      put_invoice('BF-I-1', payload.merge(invoice_date: 5.years.ago.to_date.to_s))

      expect(response).to have_http_status(:conflict)
      expect(Accounting::Invoice.count).to eq(0)
    end

    it 'answers 409, not 500, when a concurrent request already created the same reference' do
      put_invoice
      # The lost race: this request did not see the document the other one has just committed.
      allow_any_instance_of(Accounting::ExternalInvoice).to receive(:latest).and_return(nil)
      line[:unit_price] = '60.00'

      expect { put_invoice }.not_to change(Accounting::Invoice, :count)

      expect(response).to have_http_status(:conflict)
      expect(json['errors']['base'].first).to match(/retry/i)
      expect(invoices.first).to be_posted
    end

    it 'requires the invoices:write scope' do
      issued.first.update!(scopes: %w[invoices:read])

      put_invoice

      expect(response).to have_http_status(:forbidden)
    end

    it 'leaves an invoice typed in the UI alone, even with the same free-text reference' do
      typed = create(:invoice, :posted, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year, external_ref: 'BF-I-1')

      put_invoice

      expect(response).to have_http_status(:created)
      expect(typed.reload).to be_posted
      expect(json['revision']).to eq(1)
    end

    it 'does not see another entity’s document with the same external_ref' do
      ActsAsTenant.with_tenant(create(:entity)) { create(:invoice, :draft, external_ref: 'BF-I-1', external_digest: 'x') }

      put_invoice

      expect(response).to have_http_status(:created)
    end
  end

  describe 'DELETE' do
    before { put_invoice }

    it 'cancels the invoice, reverses its entry and records the reason in the audit trail' do
      delete '/api/v1/invoices/BF-I-1', params: { reason: 'Duplicate encoding' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(invoices.first).to be_cancelled
      log = Accounting::AuditLog.unscoped.find_by(action: 'reverse_entry', entity_id: entity.id)
      expect(log.reason).to eq('Duplicate encoding')
      expect(log.payload['api_client']['name']).to eq('BudgetFlow')
    end

    it 'requires a reason' do
      delete '/api/v1/invoices/BF-I-1', headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(invoices.first).to be_posted
    end

    it 'is idempotent on an already cancelled invoice' do
      2.times { delete '/api/v1/invoices/BF-I-1', params: { reason: 'x' }, headers: headers, as: :json }

      expect(response).to have_http_status(:ok)
    end

    it 'answers 409 when the invoice is paid' do
      invoices.first.update_columns(status: Accounting::Invoice.statuses[:paid])

      delete '/api/v1/invoices/BF-I-1', params: { reason: 'x' }, headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
    end

    it 'answers 404 for an unknown reference' do
      delete '/api/v1/invoices/NOPE', params: { reason: 'x' }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET' do
    it 'returns the current revision with the history and its accounting status' do
      put_invoice
      line[:unit_price] = '60.00'
      put_invoice

      get '/api/v1/invoices/BF-I-1', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json).to include('external_ref' => 'BF-I-1', 'revision' => 2, 'status' => 'posted')
      expect(json['revisions'].map { |r| [ r['revision'], r['status'] ] }).to eq([ [ 1, 'cancelled' ], [ 2, 'posted' ] ])
    end

    it 'answers 404 for an unknown reference and requires the read scope' do
      get '/api/v1/invoices/NOPE', headers: headers
      expect(response).to have_http_status(:not_found)

      issued.first.update!(scopes: %w[partners:write])
      get '/api/v1/invoices/NOPE', headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
