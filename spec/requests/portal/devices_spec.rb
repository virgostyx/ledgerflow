require 'rails_helper'

# B02a: a sign-in from a browser not seen before is told to the person; the person sees their devices and cuts one off.
RSpec.describe 'Portal devices', type: :request do
  let!(:user) { create(:portal_user) }

  before { host! Rails.configuration.x.portal_host }

  def sign_in!(headers: {})
    post '/session', params: { email: user.email, password: 'correct horse battery' }, headers: headers
    post '/second_factor/challenge', params: { code: Totp.code(user.totp_secret) }, headers: headers
  end

  def alerts = ActionMailer::Base.deliveries.select { |m| m.subject =~ /new device/i }

  it 'says nothing of the very first device (it is the person who just enrolled)' do
    expect { sign_in! }.not_to(change { alerts.size })
    expect(user.devices.count).to eq(1)
  end

  it 'does not repeat the alert on a browser already seen' do
    sign_in!
    delete '/session'
    expect { sign_in! }.not_to(change { alerts.size })
    expect(user.devices.count).to eq(1)
  end

  it 'tells the person by e-mail of a sign-in from a new browser, with the time and the address and no secret' do
    sign_in!
    reset! # another browser: no cookie
    host! Rails.configuration.x.portal_host

    expect { sign_in!(headers: { 'REMOTE_ADDR' => '8.8.4.4', 'HTTP_USER_AGENT' => 'OtherBrowser/1.0' }) }.to change { alerts.size }.by(1)

    mail = alerts.last
    expect(mail.to).to eq([ user.email ])
    expect(mail.body.to_s).to include('8.8.4.4').and include('OtherBrowser/1.0')
    expect(mail.body.to_s).not_to include(user.totp_secret)
    expect(Portal::Event.where(action: 'new_device', portal_user_id: user.id)).to exist
  end

  it 'lists the devices and cuts one off, ending its sessions' do
    sign_in!
    get '/devices'
    expect(response.body).to include('Devices').and include('This device')

    device = user.devices.sole
    delete "/devices/#{device.token}"
    expect(device.reload.revoked_at).to be_present
    get '/'
    expect(response).to redirect_to('/sign_in')
  end

  it 'never shows or touches the device of someone else' do
    other = create(:portal_user)
    foreign = Portal::Device.create!(portal_user: other, token: "foreigntoken", token_digest: "x", first_seen_at: Time.current, last_seen_at: Time.current)
    sign_in!
    delete "/devices/#{foreign.token}"
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.revoked_at).to be_nil
  end
end
