require 'rails_helper'

RSpec.describe 'Users::Sessions', type: :request do
  let(:password) { 'Password123!' }
  let!(:user) { create(:user, :accountant, password: password, active: true) }

  describe 'GET /users/sign_in' do
    it 'retourne 200 et affiche le formulaire de connexion' do
      get new_user_session_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Sign in')
    end
  end

  describe 'POST /users/sign_in' do
    context 'avec des credentials valides' do
      it 'connecte l utilisateur et redirige vers le dashboard' do
        post user_session_path, params: {
          user: { email: user.email, password: password }
        }
        expect(response).to redirect_to(accounting_root_path)
      end
    end

    context 'avec des credentials invalides' do
      it 'retourne 422 et affiche une erreur' do
        post user_session_path, params: {
          user: { email: user.email, password: 'wrong_password' }
        }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Email ou mot de passe invalide')
      end
    end

    context 'avec un compte inactif' do
      it 'refuse la connexion' do
        user.update!(active: false)
        post user_session_path, params: {
          user: { email: user.email, password: password }
        }
        expect(response).not_to redirect_to(accounting_root_path)
      end
    end
  end

  describe 'DELETE /users/sign_out' do
    it 'déconnecte l utilisateur et redirige vers la landing page' do
      sign_in user
      delete destroy_user_session_path
      expect(response).to redirect_to(root_path)
    end
  end
end
