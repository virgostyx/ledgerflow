require 'rails_helper'

# Production is closed to sign-ups: the firm creates its users itself. OPEN_SIGNUP=1 opens it (never needed at stage 1).
RSpec.describe 'Sign-up when closed', type: :request do
  around do |example|
    saved = Rails.configuration.x.open_signup
    Rails.configuration.x.open_signup = false
    example.run
  ensure
    Rails.configuration.x.open_signup = saved
  end

  let(:params) { { user: { full_name: 'Mallory', email: 'mallory@example.test', password: 'Password123!', password_confirmation: 'Password123!' } } }

  it 'sends the form back to the sign-in page' do
    get new_user_registration_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'creates no account' do
    expect { post user_registration_path, params: params }.not_to change(User, :count)
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'does not offer the link on the sign-in page' do
    get new_user_session_path
    expect(response.body).not_to include('Create an account')
  end
end
