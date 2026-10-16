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

  describe 'what the browser keeps when the person signs out (B02b)' do
    it 'clears its copies of pages, and keeps the documents waiting to be sent unless asked' do
      delete '/session'
      expect(response.headers['Clear-Site-Data']).to eq('"cache"')
    end

    it 'erases the documents waiting to be sent too when the person chose so' do
      patch '/preferences', params: { wipe_outbox_on_sign_out: '1' }
      expect(user.reload.wipe_outbox_on_sign_out).to be(true)
      expect(user.notification_frequency).to eq('immediate') # the other preference is left alone

      delete '/session'
      expect(response.headers['Clear-Site-Data']).to eq('"cache", "storage"')
    end

    it 'can be turned off again' do
      user.update!(wipe_outbox_on_sign_out: true)
      patch '/preferences', params: { wipe_outbox_on_sign_out: '0', notification_frequency: 'daily' }
      expect(user.reload).to have_attributes(wipe_outbox_on_sign_out: false, notification_frequency: 'daily')
    end
  end
end
