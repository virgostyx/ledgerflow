require 'rails_helper'

# B02a edge cases: a company that is suspended or has the portal turned off gives no access, with a neutral message; no recovery by e-mail exists.
RSpec.describe 'Portal company state', type: :request do
  let(:entity) { create(:entity) }
  let(:user)   { create(:portal_user) }

  before do
    host! Rails.configuration.x.portal_host
    Portal::Grant.create!(portal_user: user, entity_id: entity.id, role: 'director', capabilities: %w[publications.view])
    PortalAdmin::Publish.call(entity: entity, kind: 'other', title: 'Visible title', by: create(:user), files: [ { filename: 'a.pdf', content_type: 'application/pdf', data: '%PDF' } ])
    post '/session', params: { email: user.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }
  end

  it 'shows the company and its publications while all is well' do
    get '/'
    expect(response.body).to include(entity.name)
    get '/publications'
    expect(response.body).to include('Visible title')
  end

  it 'shows nothing of a suspended company, and says only that nothing is shared' do
    entity.update!(active: false)
    get '/'
    expect(response.body).not_to include(entity.name)
    expect(response.body).to include('Nothing is shared with you at the moment')
    get '/publications'
    expect(response.body).not_to include('Visible title')
  end

  it 'shows nothing where the portal was turned off' do
    entity.update!(features: { 'b02a' => false })
    get '/publications'
    expect(response.body).not_to include('Visible title')
  end

  it 'has no way to get back in by e-mail alone' do
    paths = Rails.application.routes.routes.select { |r| r.defaults[:controller].to_s.start_with?('portal/') }.map { |r| r.path.spec.to_s }
    expect(paths.grep(/recover|forgot|reset|password/i)).to be_empty
  end
end
