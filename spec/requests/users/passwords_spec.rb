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
end
