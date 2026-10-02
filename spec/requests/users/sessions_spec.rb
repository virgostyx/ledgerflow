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
        expect(response.body).to include('Invalid email or password')
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

  describe 'audit trail (F01)' do
    let(:entity) { create(:entity) }
    let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }

    def audit(action) = Accounting::AuditLog.where(action: action, auditable_id: user.id, entity_id: entity.id)

    it 'records a successful sign-in' do
      post user_session_path, params: { user: { email: user.email, password: password } }

      expect(audit('login').count).to eq(1)
      expect(audit('login').first.payload).to include('method' => 'password')
    end

    it 'records a failed sign-in with the number of failed attempts' do
      post user_session_path, params: { user: { email: user.email, password: 'wrong' } }

      row = audit('login_failed').first
      expect(row.payload).to include('method' => 'password', 'failed_attempts' => 1, 'locked' => false)
      expect(audit('login').count).to eq(0)
    end

    it 'records the lock after five failures' do
      5.times { post user_session_path, params: { user: { email: user.email, password: 'wrong' } } }

      expect(audit('login_failed').count).to eq(5)
      expect(audit('login_failed').order(:id).last.payload).to include('failed_attempts' => 5, 'locked' => true)
      expect(user.reload).to be_access_locked
    end

    it 'does not write anything for an unknown email' do
      expect { post user_session_path, params: { user: { email: 'nobody@example.com', password: 'x' } } }
        .not_to change(Accounting::AuditLog, :count)
    end
  end
end
