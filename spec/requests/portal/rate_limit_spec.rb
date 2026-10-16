require 'rails_helper'

# B02a: guessing is slowed down per address and per account, on top of the lock after five failures.
RSpec.describe 'Portal rate limits', type: :request do
  # Rack::Attack counts in fixed windows (20 seconds, a minute...): a test whose requests straddle the edge of a window would see its counter start again. The clock stands still.
  before do
    freeze_time
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    host! Rails.configuration.x.portal_host
  end

  after do
    Rack::Attack.enabled = false
    travel_back
  end

  def sign_in_try(email: 'a@client.example', ip: '1.2.3.4')
    post '/session', params: { email: email, password: 'wrong wrong wrong' }, headers: { 'REMOTE_ADDR' => ip }
  end

  it 'answers 429 to the sixth sign-in attempt in 20 seconds from one address' do
    5.times { sign_in_try }
    expect(response).not_to have_http_status(:too_many_requests)
    sign_in_try
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'answers 429 after ten attempts on one account in an hour, from as many addresses as you like' do
    10.times { |i| sign_in_try(email: 'Victim@client.example', ip: "10.0.0.#{i}") }
    sign_in_try(email: ' victim@CLIENT.example', ip: '10.9.9.9')
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'slows down the guessing of invitation tokens' do
    20.times { |i| get "/invitations/guess#{i}", headers: { 'REMOTE_ADDR' => '2.2.2.2' } }
    get '/invitations/guess21', headers: { 'REMOTE_ADDR' => '2.2.2.2' }
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'slows down the guessing of second-factor codes' do
    6.times { post '/second_factor/challenge', params: { code: '000000' }, headers: { 'REMOTE_ADDR' => '3.3.3.3' } }
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'limits the sessions opened and the chunks sent from one address (B02b)' do
    30.times { post '/uploads', headers: { 'REMOTE_ADDR' => '5.5.5.5' } }
    post '/uploads', headers: { 'REMOTE_ADDR' => '5.5.5.5' }
    expect(response).to have_http_status(:too_many_requests)

    120.times { put '/uploads/abc/chunks/0', headers: { 'REMOTE_ADDR' => '6.6.6.6' } }
    put '/uploads/abc/chunks/0', headers: { 'REMOTE_ADDR' => '6.6.6.6' }
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'does not touch the application: its own sign-in has its own budget' do
    host! 'www.example.com'
    5.times { post user_session_path, params: { user: { email: 'a@b.example', password: 'x' } }, headers: { 'REMOTE_ADDR' => '4.4.4.4' } }
    host! Rails.configuration.x.portal_host
    sign_in_try(ip: '4.4.4.4')
    expect(response).not_to have_http_status(:too_many_requests)
  end
end
