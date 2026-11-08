require 'rails_helper'

RSpec.describe 'Landing', type: :request do
  describe 'GET /' do
    it 'est accessible sans authentification' do
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it 'affiche le nom de l application' do
      get root_path
      expect(response.body).to include('LedgerFlow')
    end

    it 'contient un lien vers la page de connexion' do
      get root_path
      expect(response.body).to include(new_user_session_path)
    end

    it 'affiche le badge de conformité PCMN' do
      get root_path
      expect(response.body).to include('PCMN')
    end
  end

  describe 'live double-entry demo' do
    it 'renders the interactive demo with balanced accounts' do
      get root_path
      expect(response.body).to include('data-controller="ledger-demo"')
      expect(response.body).to include('400000', '440000', '451000', '700000')
    end
  end

  describe 'demo purchase scenario and call to action' do
    it 'offers a purchase entry and a sign-up call to action after the demo' do
      get root_path
      expect(response.body).to include('604000', '411000', 'data-ledger-demo-target="purchase"')
      expect(response.body).to match(/ledger-demo.*Create your free account.*Already have an account\?/m)
      expect(response.body).to include(new_user_registration_path)
    end
  end

  describe 'demo break button and hero link' do
    it 'offers a break-it button and a hero link to the demo anchor' do
      get root_path
      expect(response.body).to include('ledger-demo#toggleBreak', 'id="demo"', 'href="#demo"')
    end
  end

  describe 'demo structured payment reference' do
    it 'shows a valid +++OGM+++ for invoice 2026001 (2026001 mod 97 = 59)' do
      get root_path
      expect(response.body).to include('+++000/2026/00159+++')
    end
  end

  describe 'search and sharing metadata' do
    it 'has a meta description and Open Graph title/description' do
      get root_path
      expect(response.body).to include('<meta name="description"', 'property="og:title"', 'property="og:description"')
    end
  end

  describe 'demo without JavaScript' do
    it 'server-renders the default 1 000 € at 21 % figures' do
      get root_path
      expect(response.body).to include('1 000,00 €', '210,00 €', '1 210,00 €')
    end
  end

  describe 'demo payment scenario' do
    it 'offers the customer payment entry (550000 Bank / 400000 Customers)' do
      get root_path
      expect(response.body).to include('data-ledger-demo-target="payment"', '550000 Bank', 'value="payment"')
    end
  end

  describe 'hero call to action' do
    it 'leads with Get started free when signup is open' do
      get root_path
      hero = Nokogiri::HTML(response.body).at_css('main section')
      cta = hero.at_css('a.bg-primary-600')
      expect(cta.text.strip).to eq('Get started free')
      expect(cta['href']).to eq(new_user_registration_path)
    end
  end

  describe 'sign-up call to action when signup is closed' do
    around do |example|
      saved = Rails.configuration.x.open_signup
      Rails.configuration.x.open_signup = false
      example.run
      Rails.configuration.x.open_signup = saved
    end

    it 'does not advertise account creation' do
      get root_path
      expect(response.body).not_to include(new_user_registration_path)
      expect(response.body).not_to include('Create your free account')
      expect(response.body).to include('Sign in to your books')
      expect(response.body).not_to include('Get started free')
    end
  end

  describe 'Redirection des utilisateurs connectés' do
    include_context 'with entity'

    let!(:user) { create(:user, :accountant) }
    let!(:user_membership) { create(:user_entity, :accountant, user: user, entity: entity) }

    it 'redirige vers le dashboard si déjà connecté' do
      sign_in user
      get root_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end
