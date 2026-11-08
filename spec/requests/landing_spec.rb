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
    it 'offers a purchase entry and a sign-in call to action after the demo' do
      get root_path
      expect(response.body).to include('604000', '411000', 'data-ledger-demo-target="purchase"')
      expect(response.body).to match(/ledger-demo.*Sign in to start/m)
    end
  end

  describe 'demo break button and hero link' do
    it 'offers a break-it button and a hero link to the demo anchor' do
      get root_path
      expect(response.body).to include('ledger-demo#toggleBreak', 'id="demo"', 'href="#demo"')
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
