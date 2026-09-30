require 'rails_helper'

# Feed of payment events for third-party applications: they poll it with a cursor (docs/dev/api/inbound-api.md).
RSpec.describe 'Api::V1::InvoiceEvents', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'

  let!(:purchase) { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'BF-P-1') }
  let(:issued)    { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: %w[invoices:read]) }
  let(:headers)   { { 'Authorization' => "Bearer #{issued.last}" } }

  def paid_invoice(ref)
    invoice = Accounting::ExternalInvoice.upsert(
      external_ref: ref, partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s,
      lines: [ { account_code: '604000', description: 'X', quantity: '1', unit_price: '100', vat_rate: '21' } ]
    ).invoice
    invoice.pay!
    invoice
  end

  def feed(params = {}) = get('/api/v1/invoice_events', params: params, headers: headers)
  def json = JSON.parse(response.body)

  it 'lists payment events oldest first, flattened, with a cursor' do
    first  = paid_invoice('BF-I-1')
    second = paid_invoice('BF-I-2')
    travel 6.seconds

    feed

    expect(response).to have_http_status(:ok)
    expect(json['events'].map { |e| e['external_ref'] }).to eq(%w[BF-I-1 BF-I-2])
    expect(json['events'].first).to include('type' => 'paid', 'revision' => 1, 'invoice_number' => first.invoice_number,
                                            'currency' => 'EUR', 'amount_eur' => '121.0', 'paid_on' => Date.current.iso8601)
    expect(json['events'].first['id']).to be < json['events'].last['id']
    expect(json['next_cursor']).to eq(json['events'].last['id'])
    expect(second.reload).to be_paid
  end

  it 'returns only what follows the cursor, and keeps the cursor when there is nothing new' do
    paid_invoice('BF-I-1')
    paid_invoice('BF-I-2')
    travel 6.seconds
    feed
    cursor = json['events'].first['id']

    feed(after: cursor)
    expect(json['events'].map { |e| e['external_ref'] }).to eq(%w[BF-I-2])

    feed(after: json['next_cursor'])
    expect(json['events']).to eq([])
    expect(json['next_cursor']).to eq(cursor + 1)
  end

  it 'honours limit' do
    3.times { |i| paid_invoice("BF-I-#{i}") }
    travel 6.seconds

    feed(limit: 2)

    expect(json['events'].size).to eq(2)
    expect(json['next_cursor']).to eq(json['events'].last['id'])
  end

  it 'holds back events younger than the settle delay' do
    paid_invoice('BF-I-1')

    feed

    expect(json['events']).to eq([])
    travel 6.seconds
    feed
    expect(json['events'].size).to eq(1)
  end

  it 'never shows another entity’s events' do
    other = create(:entity)
    ActsAsTenant.with_tenant(other) do
      other_invoice = create(:invoice, :posted, invoice_type: :supplier, fiscal_year: create(:fiscal_year, entity: other), external_digest: 'x', external_ref: 'BF-I-1')
      Accounting::InvoiceEvent.record!(other_invoice, 'paid')
    end
    travel 6.seconds

    feed

    expect(json['events']).to eq([])
  end

  it 'requires the invoices:read scope' do
    issued.first.update!(scopes: %w[partners:write])

    feed

    expect(response).to have_http_status(:forbidden)
  end

  it 'requires authentication' do
    get '/api/v1/invoice_events'

    expect(response).to have_http_status(:unauthorized)
  end
end
