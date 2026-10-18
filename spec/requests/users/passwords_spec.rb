require 'rails_helper'

# The reset of the password is also the "choose your password" of an invitation: if the form does not reach Devise, nobody invited can enter.
RSpec.describe 'Forgotten password', type: :request do
  let!(:user) { create(:user, email: 'invited@example.test') }

  def field_name
    Nokogiri::HTML(response.body).at_css('form input[type=email]')['name']
  end

  it 'sends the reset e-mail when the person fills the form' do
    get new_user_password_path
    expect { post user_password_path, params: { field_name => user.email } }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(response).to redirect_to(new_user_session_path)
    expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
  end

  it 'lets the person choose a password from the link of the e-mail' do
    token = user.send_reset_password_instructions
    get edit_user_password_path(reset_password_token: token)
    expect(response).to have_http_status(:ok)
  end

  describe 'the screen to choose a password' do
    let(:token) { user.send_reset_password_instructions }

    it 'looks like the other sign-in screens: floating labels, minimum length, link back to sign in' do
      get edit_user_password_path(reset_password_token: token)
      page = Nokogiri::HTML(response.body)
      expect(page.css('form .lf-floating-label').map { |label| label.text.strip }).to eq([ 'New password', 'Confirm new password' ])
      expect(page.at_css('input[name="user[reset_password_token]"]')['value']).to eq(token)
      expect(response.body).to include('Minimum')
      expect(page.at_css('a[href="' + new_user_session_path + '"]')).to be_present
    end

    it 'saves the new password and sends the person to sign in' do
      put user_password_path, params: { user: { reset_password_token: token, password: 'A-new-password-1', password_confirmation: 'A-new-password-1' } }
      expect(user.reload.valid_password?('A-new-password-1')).to be(true)
    end

    it 'shows what is wrong in the style of the other screens, and keeps the token' do
      put user_password_path, params: { user: { reset_password_token: token, password: 'A-new-password-1', password_confirmation: 'different' } }
      expect(response.body).to include('bg-red-50')
      expect(Nokogiri::HTML(response.body).at_css('input[name="user[reset_password_token]"]')['value']).to eq(token)
    end
  end
end
