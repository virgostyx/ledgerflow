require 'rails_helper'

# An application (BudgetFlow) sends the invoice of a supplier abroad with that country's VAT: it asks for the treatment "foreign_vat".
RSpec.describe 'Api::V1 invoice with foreign VAT', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:journal)  { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'BF-P-1', country: 'ZM') }
  let(:issued)    { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: %w[invoices:read invoices:write]) }
  let(:headers)   { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:payload) do
    { partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s, post: false, vat_treatment: 'foreign_vat',
      lines: [ { account_code: '604000', description: 'Services', quantity: '1', unit_price: '10000', vat_rate: '16' } ] }
  end

  def put_invoice(body = payload) = put('/api/v1/invoices/BF-I-1', params: body, headers: headers, as: :json)
  def invoice = Accounting::Invoice.external.find_by(external_ref: 'BF-I-1')

  it 'takes it, with the VAT kept on the line and the whole owed to the supplier' do
    put_invoice

    expect(response).to have_http_status(:created)
    expect(invoice).to have_attributes(vat_treatment: 'foreign_vat', subtotal_excl_vat: BigDecimal('10000'), vat_amount: BigDecimal('1600'), total_incl_vat: BigDecimal('11600'))
  end

  it 'is idempotent' do
    put_invoice
    put_invoice

    expect(response).to have_http_status(:ok)
    expect(Accounting::Invoice.external.where(external_ref: 'BF-I-1').count).to eq(1)
  end

  it 'refuses it on a customer invoice' do
    put_invoice(payload.merge(invoice_type: 'customer'))

    expect(response).to have_http_status(:unprocessable_content)
  end
end
