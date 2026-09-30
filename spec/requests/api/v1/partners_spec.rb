require 'rails_helper'

RSpec.describe 'Api::V1::Partners', type: :request do
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) } # the API only exists for entities that declared BudgetFlow

  let(:scopes)  { %w[partners:write] }
  let(:issued)  { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: scopes) }
  let(:headers) { { 'Authorization' => "Bearer #{issued.last}" } }
  let(:payload) { { name: 'ACME SPRL', partner_type: 'supplier', vat_number: 'BE0123456789', country: 'BE', iban: 'BE68539007547034' } }

  def put_partner(ref = 'BF-P-1', body = payload) = put("/api/v1/partners/#{ref}", params: body, headers: headers, as: :json)

  it 'creates a partner keyed by external_ref' do
    expect { put_partner }.to change(Accounting::Partner, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)).to include('external_ref' => 'BF-P-1', 'name' => 'ACME SPRL')
    expect(Accounting::Partner.find_by(external_ref: 'BF-P-1')).to have_attributes(entity: entity, partner_type: 'supplier')
  end

  it 'is idempotent: replaying changes nothing' do
    put_partner
    expect { put_partner }.not_to change(Accounting::Partner, :count)

    expect(response).to have_http_status(:ok)
  end

  it 'updates the partner when data changes' do
    put_partner
    put_partner('BF-P-1', payload.merge(name: 'ACME NV', email: 'a@acme.be'))

    expect(response).to have_http_status(:ok)
    expect(Accounting::Partner.find_by(external_ref: 'BF-P-1')).to have_attributes(name: 'ACME NV', email: 'a@acme.be')
  end

  it 'adopts an existing partner with the same VAT number and no external_ref' do
    existing = create(:partner, :supplier, vat_number: 'BE0123456789', name: 'Old name')

    expect { put_partner }.not_to change(Accounting::Partner, :count)

    expect(existing.reload).to have_attributes(external_ref: 'BF-P-1', name: 'ACME SPRL')
  end

  it 'answers 409 when the VAT number belongs to a partner linked to another external_ref' do
    create(:partner, :supplier, vat_number: 'BE0123456789', external_ref: 'OTHER')

    put_partner

    expect(response).to have_http_status(:conflict)
  end

  it 'answers 422 with the validation errors' do
    put_partner('BF-P-1', payload.merge(vat_number: 'BE12', iban: 'nope'))

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)['errors']).to include('vat_number', 'iban')
  end

  it 'answers 422 for an unknown partner_type' do
    put_partner('BF-P-1', payload.merge(partner_type: 'alien'))

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)['errors']).to include('partner_type')
  end

  it 'answers 422 when the name is missing' do
    put_partner('BF-P-1', payload.except(:name))

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'never touches a partner of another entity' do
    other = ActsAsTenant.with_tenant(create(:entity)) { create(:partner, external_ref: 'BF-P-1') }

    put_partner

    expect(response).to have_http_status(:created)
    expect(other.reload.name).not_to eq('ACME SPRL')
  end

  it 'requires the partners:write scope' do
    issued.first.update!(scopes: %w[invoices:read])

    put_partner

    expect(response).to have_http_status(:forbidden)
  end

  it 'requires authentication' do
    put '/api/v1/partners/BF-P-1', params: payload, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
