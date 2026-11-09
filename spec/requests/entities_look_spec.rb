require 'rails_helper'

# The entity list and "add entity" pages: brand colour and their own tab titles.
RSpec.describe 'Entity pages look', type: :request do
  before { sign_in create(:user) }

  { 'My entities' => :entities_path, 'Add a new entity' => :new_entity_path }.each do |title, route|
    it "#{route} has the tab title '#{title} — LedgerFlow' and no indigo" do
      get public_send(route)
      expect(Nokogiri::HTML(response.body).at_css('title').text).to eq("#{title} — LedgerFlow")
      expect(response.body).not_to include('indigo')
    end
  end
end

RSpec.describe 'Passkeys page look', type: :request do
  it 'has its own tab title and no indigo' do
    host! 'webauthn.test'
    https!
    user = create(:user, :accountant)
    create(:user_entity, :accountant, user: user)
    sign_in user
    get passkeys_path
    expect(Nokogiri::HTML(response.body).at_css('title').text).to eq('Passkeys — LedgerFlow')
    expect(response.body).not_to include('indigo')
  end
end
