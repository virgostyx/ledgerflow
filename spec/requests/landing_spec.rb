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

  describe 'Redirection des utilisateurs connectés' do
    let!(:user) { create(:user, :accountant) }

    it 'redirige vers le dashboard si déjà connecté' do
      sign_in user
      get root_path
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end
