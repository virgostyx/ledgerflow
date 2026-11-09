require 'rails_helper'

# The public site says plainly that LedgerFlow is still being built and tested.
RSpec.describe 'Development notice on the public pages', type: :request do
  def notice = Nokogiri::HTML(response.body).at_css('[data-testid=development-notice]')

  {
    'landing page' => -> { root_path },
    'sign-in page' => -> { new_user_session_path },
    'sign-up page' => -> { new_user_registration_path }
  }.each do |name, path|
    it "is shown on the #{name}" do
      get instance_exec(&path)
      expect(notice).to be_present
      expect(notice.text).to match(/under development and testing/i)
    end
  end

  it 'comes before the rest of the page so it is the first thing read' do
    get root_path
    body = Nokogiri::HTML(response.body).at_css('body')
    expect(body.element_children.map { |e| e['data-testid'] }).to include('development-notice')
    expect(body.element_children.first['href']).to eq('#main') # skip link stays first for keyboard users
  end

  describe 'inside the application, once signed in' do
    include_context 'with entity'

    let!(:user) { create(:user, :accountant) }
    let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }

    before { sign_in user }

    {
      'main layout (dashboard)' => -> { accounting_root_path },
      'settings layout' => -> { accounting_settings_root_path }
    }.each do |name, path|
      it "is shown on the #{name}, above the header bar" do
        get instance_exec(&path)
        expect(response).to have_http_status(:ok)
        column = notice.parent
        expect(column.element_children.first['data-testid']).to eq('development-notice')
        expect(column.element_children.map(&:name)).to include('header')
      end
    end
  end
end
