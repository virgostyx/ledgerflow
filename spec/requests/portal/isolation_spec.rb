require 'rails_helper'

# B02a: the portal lives on a host of its own, with no session shared with the application, and nothing of the application is reachable from it.
RSpec.describe 'Portal isolation', type: :request do
  let(:portal_host)   { Rails.configuration.x.portal_host }
  let(:internal_host) { 'www.example.com' }

  it 'answers on the portal host, where nobody gets past the sign-in page unsigned' do
    host! portal_host
    get '/sign_in'
    expect(response).to have_http_status(:ok)
    get '/'
    expect(response).to redirect_to('/sign_in')
  end

  it 'does not answer on the portal host for a path of the application' do
    host! portal_host
    get '/users/sign_in'
    expect(response).to have_http_status(:not_found)
  end

  it 'does not answer the portal on the host of the application' do
    host! internal_host
    get '/portal_home_probe'
    expect(response).to have_http_status(:not_found)
  end

  it 'keeps the application on its own host' do
    host! internal_host
    get '/users/sign_in'
    expect(response).to have_http_status(:ok)
  end

  describe 'what the portal sends' do
    before { host! portal_host; get '/sign_in' }

    it 'sets no cookie of the application' do
      expect(response.headers['Set-Cookie'].to_s).not_to include('_ledgerflow_session')
    end

    it 'loads nothing from a third party' do
      csp = response.headers['Content-Security-Policy']
      expect(csp).to include("default-src 'none'")
      expect(csp).not_to match(%r{https?:|\*})
      expect(csp).to include("frame-ancestors 'none'")
    end

    it 'carries the security headers' do
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(response.headers['Referrer-Policy']).to eq('no-referrer')
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.headers['X-Robots-Tag']).to include('noindex')
      expect(response.headers['Permissions-Policy']).to be_present
    end
  end

  describe 'forgery protection' do
    around do |example|
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it 'refuses a form posted from elsewhere, and keeps its token in a cookie of its own rather than in the session of the application' do
      host! portal_host
      get '/sign_in'
      expect(response.headers['Set-Cookie'].to_s).not_to include('_ledgerflow_session')

      post '/session', params: { email: 'a@b.example', password: 'whatever whatever' }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end

RSpec.describe 'Portal database role', type: :request do
  before { host! Rails.configuration.x.portal_host }

  it 'goes through the connection of the portal when the deployment gave it one' do
    allow(Portal).to receive(:restricted_database?).and_return(true)
    expect(ApplicationRecord).to receive(:connected_to).with(role: :portal).and_call_original

    get '/sign_in'
    expect(response).to have_http_status(:ok)
  end

  it 'uses the connection of the application otherwise' do
    expect(ApplicationRecord).not_to receive(:connected_to)
    get '/sign_in'
    expect(response).to have_http_status(:ok)
  end
end
