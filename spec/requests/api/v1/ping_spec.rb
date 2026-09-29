require 'rails_helper'

# Connection check for third-party health_check calls: any active client may call it, whatever its scopes.
RSpec.describe 'Api::V1::Ping', type: :request do
  include_context 'with_open_fiscal_year'

  let(:client_and_key) { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: []) }
  let(:headers)        { { 'Authorization' => "Bearer #{client_and_key.last}" } }

  it 'answers 200 with who the caller is, even without any scope' do
    get '/api/v1/ping', headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include('status' => 'ok', 'entity' => entity.name, 'api_client' => 'BudgetFlow', 'scopes' => [])
    expect(body['time']).to be_present
  end

  it 'lists the granted scopes' do
    client_and_key.first.update!(scopes: %w[invoices:read partners:write])

    get '/api/v1/ping', headers: headers

    expect(JSON.parse(response.body)['scopes']).to eq(%w[invoices:read partners:write])
  end

  it 'answers 401 for a missing, unknown or revoked key' do
    get '/api/v1/ping'
    expect(response).to have_http_status(:unauthorized)

    get '/api/v1/ping', headers: { 'Authorization' => 'Bearer lf_unknown' }
    expect(response).to have_http_status(:unauthorized)

    client_and_key.first.revoke!
    get '/api/v1/ping', headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'is logged like any other call' do
    expect { get '/api/v1/ping', headers: headers }.to change { client_and_key.first.api_requests.count }.by(1)
  end
end
