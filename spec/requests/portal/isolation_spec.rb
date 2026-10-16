require 'rails_helper'

# B02a: the portal lives on a host of its own, with no session shared with the application, and nothing of the application is reachable from it.
RSpec.describe 'Portal isolation', type: :request do
  let(:portal_host)   { Rails.configuration.x.portal_host }
  let(:internal_host) { 'www.example.com' }

  it 'answers on the portal host' do
    host! portal_host
    get '/'
    expect(response).to have_http_status(:ok)
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
    before { host! portal_host; get '/' }

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
end
