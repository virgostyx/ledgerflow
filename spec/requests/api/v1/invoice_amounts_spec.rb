require 'rails_helper'

# What BudgetFlow's reconciliation compares: currency, rate, the amounts in the currency of the document and the total in euros.
RSpec.describe 'Api::V1 invoice amounts', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:journal)  { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'bf-supplier-1') }
  let(:issued)    { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: %w[invoices:read invoices:write]) }
  let(:headers)   { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:payload) do
    { partner_external_ref: 'bf-supplier-1', invoice_type: 'supplier', invoice_date: Date.current.to_s, post: false,
      currency: 'USD', exchange_rate: '1.25',
      lines: [ { account_code: '604000', description: 'X', quantity: '2', unit_price: '50.00', vat_rate: '10' } ] }
  end
  let(:amounts) do
    { 'currency' => 'USD', 'exchange_rate' => '1.25', 'subtotal_excl_vat' => '100.0', 'vat_amount' => '10.0',
      'total_incl_vat' => '110.0', 'total_incl_vat_eur' => '88.0' }
  end

  before { put '/api/v1/invoices/bf-invoice-1', params: payload, headers: headers, as: :json }

  it 'gives them with a single document' do
    get '/api/v1/invoices/bf-invoice-1', headers: headers

    expect(JSON.parse(response.body)).to include(amounts)
  end

  it 'gives them in the list too' do
    get '/api/v1/invoices', headers: headers

    expect(JSON.parse(response.body).first).to include(amounts)
  end
end
