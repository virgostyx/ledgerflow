require 'rails_helper'

# The first screen a new account sees: in the brand colour (primary), with its own tab title.
RSpec.describe 'First-entity page', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    get new_onboarding_entity_path
  end

  it 'has its own tab title' do
    expect(Nokogiri::HTML(response.body).at_css('title').text).to eq('Create your accounting entity — LedgerFlow')
  end

  it 'uses the brand colour, not indigo' do
    expect(response.body).not_to include('indigo')
    expect(response.body).to include('bg-primary-600')
  end
end
