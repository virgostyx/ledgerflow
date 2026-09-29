require 'rails_helper'

# Credit notes go through the same endpoint as invoices (docs/dev/api/inbound-api.md): document_type +
# an optional link to the credited invoice, same idempotence / revisions / cancellation.
RSpec.describe 'Api::V1 credit notes', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'

  let!(:journal)  { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'BF-P-1') }
  let(:issued)    { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: %w[invoices:read invoices:write]) }
  let(:headers)   { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:line)      { { account_code: '604000', description: 'Consulting', quantity: '2', unit_price: '50.00', vat_rate: '21' } }
  let(:invoice_payload) do
    { partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s, lines: [ line ] }
  end
  let(:credit_line) { { account_code: '604000', description: 'Refund', quantity: '1', unit_price: '50.00', vat_rate: '21' } }
  let(:credit_payload) do
    { document_type: 'credit_note', credited_invoice_external_ref: 'BF-I-1', partner_external_ref: 'BF-P-1',
      invoice_type: 'supplier', invoice_date: Date.current.to_s, lines: [ credit_line ] }
  end

  def put_doc(ref, body) = put("/api/v1/invoices/#{ref}", params: body, headers: headers, as: :json)
  def json = JSON.parse(response.body)
  def doc(ref) = Accounting::Invoice.external.where(external_ref: ref).order(:revision)
  def original = doc('BF-I-1').first

  before { put_doc('BF-I-1', invoice_payload) }

  it 'posts a credit note linked to the credited invoice' do
    put_doc('BF-CN-1', credit_payload)

    expect(response).to have_http_status(:created)
    note = doc('BF-CN-1').first
    expect(note).to have_attributes(document_type: 'credit_note', status: 'posted', credited_invoice_id: original.id,
                                    total_incl_vat: BigDecimal('60.5'))
    expect(note.journal_entry).to be_posted
    expect(json).to include('document_type' => 'credit_note', 'credited_invoice_external_ref' => 'BF-I-1')
  end

  it 'reduces what is left to pay on the credited invoice at once' do
    put_doc('BF-CN-1', credit_payload)

    expect(original.reload.remaining_amount).to eq(BigDecimal('60.5'))
  end

  it 'is idempotent' do
    put_doc('BF-CN-1', credit_payload)
    count = Accounting::Invoice.count

    put_doc('BF-CN-1', credit_payload)

    expect(response).to have_http_status(:ok)
    expect(Accounting::Invoice.count).to eq(count)
  end

  it 'accepts a credit note that is not linked to any invoice' do
    put_doc('BF-CN-2', credit_payload.except(:credited_invoice_external_ref))

    expect(response).to have_http_status(:created)
    expect(doc('BF-CN-2').first.credited_invoice).to be_nil
  end

  it 'refuses, with 422 and nothing written, a credit that exceeds the invoice' do
    credit_line[:quantity] = '3' # 3 x 50 + 21% = 181.5 > 121

    expect { put_doc('BF-CN-1', credit_payload) }.not_to change(Accounting::Invoice, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json['errors']['base'].first).to match(/exceed/i)
  end

  it 'answers 422 for an unknown, cancelled or credit-note reference to credit' do
    put_doc('BF-CN-1', credit_payload.merge(credited_invoice_external_ref: 'NOPE'))
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['errors']['credited_invoice_external_ref']).to be_present

    put_doc('BF-CN-9', credit_payload)
    put_doc('BF-CN-1', credit_payload.merge(credited_invoice_external_ref: 'BF-CN-9'))
    expect(response).to have_http_status(:unprocessable_content)

    delete '/api/v1/invoices/BF-I-1', params: { reason: 'x' }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict) # credited by BF-CN-9, cannot be cancelled first

    delete '/api/v1/invoices/BF-CN-9', params: { reason: 'x' }, headers: headers, as: :json
    delete '/api/v1/invoices/BF-I-1', params: { reason: 'x' }, headers: headers, as: :json
    put_doc('BF-CN-1', credit_payload)
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['errors']['credited_invoice_external_ref']).to be_present
  end

  it 'answers 422 when the credited partner differs' do
    create(:partner, :supplier, external_ref: 'BF-P-2')

    put_doc('BF-CN-1', credit_payload.merge(partner_external_ref: 'BF-P-2'))

    expect(response).to have_http_status(:unprocessable_content)
    expect(json['errors']['credited_invoice']).to be_present
  end

  it 'refuses a link on a plain invoice and an unknown document_type' do
    put_doc('BF-I-2', invoice_payload.merge(credited_invoice_external_ref: 'BF-I-1'))
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['errors']['credited_invoice_external_ref']).to be_present

    put_doc('BF-I-3', invoice_payload.merge(document_type: 'proforma'))
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['errors']['document_type']).to be_present
  end

  it 'does not let a reference change from invoice to credit note' do
    put_doc('BF-I-1', credit_payload.except(:credited_invoice_external_ref))

    expect(response).to have_http_status(:unprocessable_content)
    expect(json['errors']['document_type']).to be_present
    expect(original).to be_posted
  end

  it 'revises a credit note by reversal, and the invoice balance follows' do
    put_doc('BF-CN-1', credit_payload)
    credit_line[:unit_price] = '20.00'

    put_doc('BF-CN-1', credit_payload)

    expect(response).to have_http_status(:ok)
    expect(doc('BF-CN-1').map(&:status)).to eq(%w[cancelled posted])
    expect(original.reload.remaining_amount).to eq(BigDecimal('96.8')) # 121 - 24.2
  end

  it 'cancels a credit note and gives the balance back' do
    put_doc('BF-CN-1', credit_payload)

    delete '/api/v1/invoices/BF-CN-1', params: { reason: 'Issued by mistake' }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(doc('BF-CN-1').first).to be_cancelled
    expect(original.reload.remaining_amount).to eq(BigDecimal('121'))
  end

  it 'refuses to revise the credited invoice while a credit note stands (409)' do
    put_doc('BF-CN-1', credit_payload)
    line[:unit_price] = '60.00'

    put_doc('BF-I-1', invoice_payload)

    expect(response).to have_http_status(:conflict)
    expect(original).to be_posted
  end

  it 'shows the document type and the credited reference on GET' do
    put_doc('BF-CN-1', credit_payload)

    get '/api/v1/invoices/BF-CN-1', headers: headers

    expect(json).to include('document_type' => 'credit_note', 'credited_invoice_external_ref' => 'BF-I-1')
  end
end
