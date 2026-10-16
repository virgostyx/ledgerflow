require 'rails_helper'

# B02a: invitation -> password -> second factor (compulsory) -> pages. No way in with a password alone, none by e-mail alone.
RSpec.describe 'Portal sign-in', type: :request do
  let(:entity) { create(:entity) }
  let(:staff)  { create(:user) }
  let(:password) { 'correct horse battery' }

  before { host! Rails.configuration.x.portal_host }

  def invite!
    Portal::Invitation.issue!(entity: entity, email: 'ann@client.example', full_name: 'Ann Client', role: 'director', by: staff)
  end

  def sign_in_with(user, secret: nil)
    post '/session', params: { email: user.email, password: password }
    post '/second_factor/challenge', params: { code: Totp.code(secret || user.totp_secret) } if user.second_factor_configured?
  end

  describe 'accepting an invitation' do
    it 'shows the form for a valid token and nothing for another' do
      _, token = invite!
      get "/invitations/#{token}"
      expect(response).to have_http_status(:ok)
      get '/invitations/nonsense'
      expect(response).to have_http_status(:not_found)
    end

    it 'sets the password, then asks for the second factor before anything else' do
      invitation, token = invite!
      post "/invitations/#{token}", params: { password: password, password_confirmation: password }
      expect(response).to redirect_to('/second_factor/new')

      get '/'
      expect(response).to redirect_to('/second_factor/new')
      expect(invitation.reload.used_at).to be_present
    end

    it 'refuses a password that is too short and keeps the invitation usable' do
      invitation, token = invite!
      post "/invitations/#{token}", params: { password: 'short', password_confirmation: 'short' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(invitation.reload.used_at).to be_nil
    end

    it 'cannot be used twice' do
      _, token = invite!
      post "/invitations/#{token}", params: { password: password, password_confirmation: password }
      get "/invitations/#{token}"
      expect(response).to have_http_status(:not_found)
    end

    it 'gives access only when a code of the app is confirmed, then shows the backup codes once' do
      _, token = invite!
      post "/invitations/#{token}", params: { password: password, password_confirmation: password }
      user = PortalUser.find_by_email('ann@client.example')

      get '/second_factor/new'
      expect(response.body).to include(user.reload.totp_secret)

      post '/second_factor', params: { code: '000000' }
      expect(response).to have_http_status(:unprocessable_content)
      get '/'
      expect(response).to redirect_to('/second_factor/new')

      post '/second_factor', params: { code: Totp.code(user.totp_secret) }
      expect(response).to have_http_status(:ok)
      expect(user.reload).to be_active
      expect(user.backup_codes.count).to eq(10)

      get '/'
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'signing in' do
    let!(:user) { create(:portal_user) }

    it 'asks for the code of the app after the password' do
      post '/session', params: { email: user.email, password: password }
      expect(response).to redirect_to('/second_factor/challenge')
      get '/'
      expect(response).to redirect_to('/second_factor/challenge')
    end

    it 'lets in with the password and the code' do
      sign_in_with(user)
      get '/'
      expect(response).to have_http_status(:ok)
    end

    it 'lets in with a backup code, once' do
      code = user.generate_backup_codes!.first
      post '/session', params: { email: user.email, password: password }
      post '/second_factor/challenge', params: { code: code }
      get '/'
      expect(response).to have_http_status(:ok)

      delete '/session'
      post '/session', params: { email: user.email, password: password }
      post '/second_factor/challenge', params: { code: code }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'says the same thing for an unknown address and a wrong password' do
      post '/session', params: { email: 'nobody@client.example', password: password }
      unknown = response.body
      post '/session', params: { email: user.email, password: 'wrong wrong wrong' }
      expect(response.body).to eq(unknown)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'locks the account after five failures, even with the right password afterwards' do
      5.times { post '/session', params: { email: user.email, password: 'wrong wrong wrong' } }
      post '/session', params: { email: user.email, password: password }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload).to be_locked
    end

    it 'counts a wrong code of the app as a failure too' do
      post '/session', params: { email: user.email, password: password }
      5.times { post '/second_factor/challenge', params: { code: '000000' } }
      expect(user.reload).to be_locked
      post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }
      get '/'
      expect(response).to redirect_to('/sign_in')
    end

    it 'refuses a suspended person' do
      user.update!(status: 'suspended')
      post '/session', params: { email: user.email, password: password }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'signs out and the old cookie is dead' do
      sign_in_with(user)
      cookie = response.request.cookie_jar[:lf_portal]
      delete '/session'
      get '/'
      expect(response).to redirect_to('/sign_in')
      expect(Portal::Session.where(portal_user_id: user.id, revoked_at: nil)).to be_empty
      expect(cookie).to be_present
    end

    it 'ends the session after 30 idle minutes' do
      sign_in_with(user)
      travel_to(31.minutes.from_now) do
        get '/'
        expect(response).to redirect_to('/sign_in')
      end
    end

    it 'takes a revocation into account at the very next request' do
      sign_in_with(user)
      user.update!(status: 'revoked')
      get '/'
      expect(response).to redirect_to('/sign_in')
    end

    it 'does not open a page with the cookie of the application' do
      get '/', headers: { 'Cookie' => '_ledgerflow_session=abc; lf_portal=abc' }
      expect(response).to redirect_to('/sign_in')
    end
  end

  describe 'recording' do
    let!(:user) { create(:portal_user) }

    it 'records the sign-ins, the failures and the sign-outs' do
      post '/session', params: { email: user.email, password: 'wrong wrong wrong' }
      sign_in_with(user)
      delete '/session'

      expect(Portal::Event.order(:id).pluck(:action)).to eq(%w[sign_in_failed sign_in second_factor_passed sign_out])
      expect(Portal::Event.first.email_tried).to eq(user.email)
    end
  end
end
