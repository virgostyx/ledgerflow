require 'rails_helper'

RSpec.describe 'Titles of the pages a visitor lands on', type: :request do
  def title = Nokogiri::HTML(response.body).at_css('title').text

  it 'names the sign-in page' do
    get new_user_session_path
    expect(title).to eq('Sign in — LedgerFlow')
  end

  it 'names the sign-up page' do
    get new_user_registration_path
    expect(title).to eq('Create your account — LedgerFlow')
  end

  it 'keeps a plain title on the other account pages' do
    get new_user_password_path
    expect(title).to eq('LedgerFlow')
  end
end
