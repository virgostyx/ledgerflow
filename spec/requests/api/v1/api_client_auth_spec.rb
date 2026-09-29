require 'rails_helper'

RSpec.describe 'Api::V1 API-key authentication', type: :request do
  include_context 'with_open_fiscal_year'

  let(:scopes)  { %w[invoices:read] }
  let(:issued)  { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: scopes) }
  let(:client)  { issued.first }
  let(:key)     { issued.last }
  let(:headers) { { 'Authorization' => "Bearer #{key}" } }

  it 'accepts a valid key with the right scope' do
    get '/api/v1/invoices', headers: headers

    expect(response).to have_http_status(:ok)
  end

  it 'scopes data to the client entity, not to the request' do
    other = create(:entity)
    ActsAsTenant.with_tenant(other) { create(:partner) }
    create(:invoice, :draft, partner: create(:partner), fiscal_year: fiscal_year)

    get '/api/v1/invoices', headers: headers

    expect(JSON.parse(response.body).size).to eq(1)
  end

  it 'answers 403 when the scope is missing' do
    client.update!(scopes: %w[partners:write])

    get '/api/v1/invoices', headers: headers

    expect(response).to have_http_status(:forbidden)
  end

  it 'answers 401 for a revoked key' do
    client.revoke!

    get '/api/v1/invoices', headers: headers

    expect(response).to have_http_status(:unauthorized)
  end

  it 'answers 401 for an unknown key' do
    get '/api/v1/invoices', headers: { 'Authorization' => 'Bearer lf_unknown' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'logs the call and stamps last_used_at' do
    expect { get '/api/v1/invoices', headers: headers }.to change { client.api_requests.count }.by(1)

    log = client.api_requests.last
    expect(log).to have_attributes(http_method: 'GET', path: '/api/v1/invoices', status: 200)
    expect(client.reload.last_used_at).to be_present
  end

  it 'logs refused calls too' do
    client.update!(scopes: [])

    get '/api/v1/invoices', headers: headers

    expect(client.api_requests.last.status).to eq(403)
  end

  it 'keeps accepting the legacy JWT (deprecated) with full access' do
    jwt = Api::JwtService.encode({ client: 'budgetflow', entity_id: entity.id })

    get '/api/v1/invoices', headers: { 'Authorization' => "Bearer #{jwt}" }

    expect(response).to have_http_status(:ok)
  end
end
