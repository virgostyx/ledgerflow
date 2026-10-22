require 'rails_helper'

# Contract with BudgetFlow: both quote a foreign currency per 1 EUR (EUR = amount / rate), so its adapter sends the rate as it is.
# The body below is the one BudgetFlow's exporter spec expects for a USD invoice at 1.0834 (spec/services/accounting/ledgerflow/exporter_spec.rb);
# change one side and the other must follow.
RSpec.describe 'Api::V1 exchange rate contract with BudgetFlow', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:journal)  { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'bf-supplier-1') }
  let!(:suspense) { create(:account, code: '499000', label_fr: "Comptes d'attente", account_class: 4, entity: entity) } # BudgetFlow sends no account
  let(:issued)    { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: %w[invoices:read invoices:write]) }
  let(:headers)   { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:payload) do
    { document_type: 'invoice', post: false, invoice_type: 'supplier', partner_external_ref: 'bf-supplier-1',
      invoice_date: Date.current.to_s, currency: 'USD', exchange_rate: '1.0834',
      lines: [ { description: 'Consulting', quantity: '1.0', unit_price: '100.0', vat_rate: '0.0' } ] }
  end

  it 'books a USD invoice at amount / rate, not amount * rate' do
    put '/api/v1/invoices/bf-invoice-1', params: payload, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    invoice = Accounting::Invoice.external.find_by!(external_ref: 'bf-invoice-1')
    expect(invoice.exchange_rate).to eq(BigDecimal('1.0834'))
    expect(invoice.total_incl_vat_eur).to eq(BigDecimal('92.30')) # 100 / 1.0834; the inverted rate would give 108.34
  end
end
