require 'rails_helper'

# B02a: the firm's look on the portal: served from the portal's own host (no inline style, no third party), the neutral one when there is none or several.
RSpec.describe 'Portal branding', type: :request do
  let(:entity) { create(:entity) }
  let(:user)   { create(:portal_user) }
  let(:png)    { "\x89PNG\r\n\x1A\n".b + ('x' * 50) }

  before do
    host! Rails.configuration.x.portal_host
    Portal::Grant.create!(portal_user: user, entity_id: entity.id, role: 'director', capabilities: %w[publications.view])
    post '/session', params: { email: user.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }
  end

  it 'serves the colours of the only company of the person as a stylesheet of the portal' do
    Portal::Branding.create!(entity_id: entity.id, display_name: 'Fiduciaire Martin', primary_color: '#0b5394', background_color: '#ffffff')
    get '/branding.css'

    expect(response.media_type).to eq('text/css')
    expect(response.body).to include('#0b5394').and include('#ffffff')
    get '/'
    expect(response.body).to include('Fiduciaire Martin').and include('/branding.css')
  end

  it 'serves the neutral look when the person has several companies, or none branded' do
    Portal::Branding.create!(entity_id: entity.id, display_name: 'Fiduciaire Martin', primary_color: '#0b5394', background_color: '#ffffff')
    Portal::Grant.create!(portal_user: user, entity_id: create(:entity).id, role: 'reader', capabilities: [])
    get '/branding.css'
    expect(response.body).not_to include('#0b5394')
  end

  it 'serves the logo of the company of the person, as an image that cannot be taken for anything else' do
    Portal::Branding.create!(entity_id: entity.id, display_name: 'Martin', logo: png, logo_content_type: 'image/png')
    get '/branding/logo'
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('image/png')
    expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    expect(response.body.b).to eq(png)
  end

  it 'has no logo to serve for a company without one' do
    get '/branding/logo'
    expect(response).to have_http_status(:not_found)
  end

  it 'keeps the content security policy: no inline style, no third party, whatever the colours' do
    Portal::Branding.create!(entity_id: entity.id, display_name: 'Martin', primary_color: '#0b5394')
    get '/'
    expect(response.body).not_to match(/<style|style="/)
    expect(response.headers['Content-Security-Policy']).not_to match(%r{https?:|\*|unsafe-inline})
  end
end
