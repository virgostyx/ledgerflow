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

  it 'names the forgotten-password page' do
    get new_user_password_path
    expect(title).to eq('Forgot your password? — LedgerFlow')
  end

  it 'names the recovery-code page' do
    get new_recovery_code_session_path
    expect(title).to eq('Use a recovery code — LedgerFlow')
  end

  # Pages behind a sign-in cannot be fetched here: their view files must still carry the title of their heading.
  Dir[Rails.root.join('app/views/users/{passwords,recovery_code_sessions,two_factor}/*.html.erb')].each do |file|
    it "titles #{Pathname(file).relative_path_from(Rails.root)} after its heading" do
      source = File.read(file)
      heading = source[%r{<h2[^>]*>(.*?)</h2>}, 1]
      expect(source).to include("content_for :title, \"#{heading} — LedgerFlow\"")
    end
  end
end

RSpec.describe 'Legibility of the small print on the sign-in and sign-up pages', type: :request do
  # text-gray-400 on white is about 2.5:1, under the 4.5:1 WCAG AA asks of small text.
  it 'uses no text-gray-400' do
    [ new_user_session_path, new_user_registration_path ].each do |path|
      get path
      expect(response.body).not_to include('text-gray-400'), "#{path} still has text-gray-400"
    end
  end
end
