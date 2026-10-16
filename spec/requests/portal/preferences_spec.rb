require 'rails_helper'

RSpec.describe 'Portal preferences', type: :request do
  let!(:user) { create(:portal_user) }

  before do
    host! Rails.configuration.x.portal_host
    post '/session', params: { email: user.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }
  end

  it 'lets the person choose how often they are told, and says security alerts are always sent' do
    get '/preferences'
    expect(response.body).to include('Security alerts are always sent')

    patch '/preferences', params: { notification_frequency: 'daily' }
    expect(user.reload.notification_frequency).to eq('daily')
  end

  it 'refuses a frequency it does not know' do
    patch '/preferences', params: { notification_frequency: 'hourly' }
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.notification_frequency).to eq('immediate')
  end
end
