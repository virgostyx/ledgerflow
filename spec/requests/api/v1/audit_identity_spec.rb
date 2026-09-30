require 'rails_helper'

# R18: writes made through the API must be attributable to the calling application.
RSpec.describe 'API audit identity', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) } # the API only exists for entities that declared BudgetFlow

  let!(:journal) { create(:journal, :purchase, default_account: account_440) }
  let(:client)   { ApiClient.issue!(entity: entity, name: 'BudgetFlow', scopes: %w[partners:write]).tap { |c| @key = c.last }.first }
  let(:headers)  { { 'Authorization' => "Bearer #{@key}" } }

  def logs_for(type) = Accounting::AuditLog.unscoped.where(entity_id: entity.id, auditable_type: type).order(:id)

  it 'audits a partner written through the API, naming the client' do
    client
    put '/api/v1/partners/P1', params: { name: 'ACME', partner_type: 'supplier' }, headers: headers, as: :json
    put '/api/v1/partners/P1', params: { name: 'ACME NV', partner_type: 'supplier' }, headers: headers, as: :json

    created, updated = logs_for('Accounting::Partner').to_a
    expect(created).to have_attributes(action: 'create', user_id: nil)
    expect(created.payload['api_client']).to eq('id' => client.id, 'name' => 'BudgetFlow')
    expect(created.request_id).to be_present
    expect(created.ip_address).to be_present
    expect(updated.payload['changes']['name']).to eq([ 'ACME', 'ACME NV' ])
    expect(Accounting::AuditVerifier.call(entity: entity)).to be_intact
  end

  it 'does not leak the client into a later web request (Current is reset)' do
    client
    put '/api/v1/partners/P1', params: { name: 'ACME', partner_type: 'supplier' }, headers: headers, as: :json

    expect(Current.api_client).to be_nil
  end

  it 'gives writes made through the legacy JWT path their request context, without a client identity' do
    jwt = Api::JwtService.encode({ entity_id: entity.id })
    put '/api/v1/partners/P1', params: { name: 'ACME', partner_type: 'supplier' },
                               headers: { 'Authorization' => "Bearer #{jwt}" }, as: :json

    expect(response).to have_http_status(:created)
    row = logs_for('Accounting::Partner').first
    expect(row.request_id).to be_present
    expect(row.payload).not_to have_key('api_client')
  end
end
