require 'rails_helper'

# Project context sent with an invoice (BudgetFlow project name and budget line chapter.line.sub_line), so the accountant
# can choose the analytical accounts in LedgerFlow.
RSpec.describe 'Api::V1 invoice project context', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:journal)  { create(:journal, :purchase, default_account: account_440) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'BF-P-1') }
  let(:issued)    { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: %w[invoices:read invoices:write]) }
  let(:headers)   { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:payload) do
    { partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s,
      project_name: 'Water Access Zambia', budget_line: '3.2.1',
      lines: [ { account_code: '604000', description: 'X', quantity: '1', unit_price: '100', vat_rate: '21' } ] }
  end

  def put_invoice(body = payload) = put('/api/v1/invoices/BF-I-1', params: body, headers: headers, as: :json)
  def json = JSON.parse(response.body)
  def invoice = Accounting::Invoice.external.find_by(external_ref: 'BF-I-1')

  it 'stores the project name and the budget line, and returns them' do
    put_invoice

    expect(response).to have_http_status(:created)
    expect(invoice).to have_attributes(external_project_name: 'Water Access Zambia', external_budget_line: '3.2.1')
    expect(json).to include('project_name' => 'Water Access Zambia', 'budget_line' => '3.2.1')
    get '/api/v1/invoices/BF-I-1', headers: headers
    expect(json).to include('project_name' => 'Water Access Zambia', 'budget_line' => '3.2.1')
  end

  it "stores the supplier's own invoice number and returns it" do
    put_invoice(payload.merge(supplier_reference: ' SUP-2026-001 '))

    expect(invoice.supplier_reference).to eq('SUP-2026-001')
    expect(json['supplier_reference']).to eq('SUP-2026-001')
  end

  it 'counts a changed supplier number as a real change (new revision)' do
    put_invoice(payload.merge(supplier_reference: 'SUP-1'))
    put_invoice(payload.merge(supplier_reference: 'SUP-2'))

    expect(Accounting::Invoice.external.where(external_ref: 'BF-I-1').order(:revision).map(&:supplier_reference)).to eq(%w[SUP-1 SUP-2])
  end

  it 'treats blank values as absent' do
    put_invoice(payload.merge(project_name: ' ', budget_line: ''))

    expect(invoice).to have_attributes(external_project_name: nil, external_budget_line: nil)
  end

  it 'replays idempotently, and a new budget line is a real change (new revision)' do
    put_invoice
    put_invoice
    expect(response).to have_http_status(:ok)
    expect(Accounting::Invoice.external.where(external_ref: 'BF-I-1').count).to eq(1)

    put_invoice(payload.merge(budget_line: '3.2.2'))

    expect(response).to have_http_status(:ok)
    expect(Accounting::Invoice.external.where(external_ref: 'BF-I-1').order(:revision).last)
      .to have_attributes(revision: 2, external_budget_line: '3.2.2')
  end
end
