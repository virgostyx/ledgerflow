require 'rails_helper'

# The coffee button stays everywhere; its pop-up message only appears on the public page, never over working screens.
RSpec.describe 'Donation widget', type: :request do
  def widget = Nokogiri::HTML(response.body).at_css('script[data-name="BMC-Widget"]')

  it 'greets visitors with its message on the public page' do
    get root_path
    expect(widget['data-id']).to eq('virgostyx')
    expect(widget['data-message']).to be_present
  end

  context 'inside the application' do
    include_context 'with entity'

    let!(:user) { create(:user, :accountant) }
    let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }

    before { sign_in user }

    { 'dashboard' => -> { accounting_root_path }, 'settings' => -> { accounting_settings_root_path } }.each do |name, path|
      it "keeps the button on the #{name} but not the pop-up message" do
        get instance_exec(&path)
        expect(widget['data-id']).to eq('virgostyx')
        expect(widget['data-message']).to be_blank
      end
    end
  end
end
