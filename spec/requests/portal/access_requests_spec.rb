require 'rails_helper'

# B02a: nobody from outside invites anyone. A director asks; the firm grants (an invitation goes out) or declines.
RSpec.describe 'Portal access requests', type: :request do
  let(:entity)   { create(:entity) }
  let(:director) { create(:portal_user) }
  let(:reader)   { create(:portal_user) }

  def sign_in!(user)
    post '/session', params: { email: user.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }
  end

  before do
    host! Rails.configuration.x.portal_host
    Portal::Grant.create!(portal_user: director, entity_id: entity.id, role: 'director', capabilities: Portal::ROLE_CAPABILITIES['director'])
    Portal::Grant.create!(portal_user: reader, entity_id: entity.id, role: 'reader', capabilities: [])
  end

  it 'lets a director ask for the access of another person, which only records the request' do
    sign_in!(director)
    expect {
      post '/access_requests', params: { company: Portal::Company.find(entity.id).id, email: 'new@client.example', full_name: 'New Person', role: 'collaborator', note: 'our new bookkeeper' }
    }.to change { Portal::AccessRequest.count }.by(1)

    expect(PortalUser.find_by_email('new@client.example')).to be_nil
    expect(Portal::Invitation.count).to eq(0)
    expect(Portal::Event.where(action: 'access_requested')).to exist
  end

  it 'refuses a person without the right to ask, and a company they have no right in' do
    sign_in!(reader)
    post '/access_requests', params: { company: entity.id, email: 'new@client.example', full_name: 'N', role: 'reader' }
    expect(response).to have_http_status(:not_found)
    expect(Portal::AccessRequest.count).to eq(0)
  end

  it 'cannot ask for a role it does not know' do
    sign_in!(director)
    post '/access_requests', params: { company: entity.id, email: 'new@client.example', full_name: 'N', role: 'owner' }
    expect(response).to have_http_status(:unprocessable_content)
  end
end

RSpec.describe 'Portal access requests (firm side)', type: :request do
  include_context 'with entity'

  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:director)   { create(:portal_user) }
  let!(:ask) { Portal::AccessRequest.create!(entity_id: entity.id, requested_by: director, token: 'tok', email: 'new@client.example', full_name: 'New Person', role: 'collaborator') }

  before { sign_in accountant }

  it 'shows the pending requests' do
    get accounting_portal_access_index_path
    expect(response.body).to include('new@client.example').and include('Access requested')
  end

  it 'grants a request by inviting, and records the decision' do
    expect { post grant_accounting_portal_access_request_path(ask.token) }.to change { Portal::Invitation.count }.by(1)

    expect(ask.reload).to have_attributes(status: 'granted', decided_by_id: accountant.id)
  end

  it 'declines a request' do
    post decline_accounting_portal_access_request_path(ask.token)
    expect(ask.reload.status).to eq('declined')
    expect(Portal::Invitation.count).to eq(0)
  end

  it 'does not decide twice, nor the request of another company' do
    post decline_accounting_portal_access_request_path(ask.token)
    expect { post grant_accounting_portal_access_request_path(ask.token) }.not_to(change { Portal::Invitation.count })
    foreign = Portal::AccessRequest.create!(entity_id: create(:entity).id, requested_by: director, token: 'other', email: 'x@client.example', full_name: 'X', role: 'reader')
    post grant_accounting_portal_access_request_path(foreign.token)
    expect(response).to have_http_status(:not_found)
  end
end
