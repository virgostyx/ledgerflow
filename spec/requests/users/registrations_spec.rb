require 'rails_helper'

RSpec.describe 'Users::Registrations', type: :request do
  let(:valid_params) do
    {
      user: {
        full_name:             'Alice Test',
        email:                 'alice.test.new@example.com',
        password:              'Password123!',
        password_confirmation: 'Password123!'
      }
    }
  end

  describe 'GET /users/sign_up' do
    it 'returns 200' do
      get new_user_registration_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /users' do
    it 'creates a new user' do
      expect {
        post user_registration_path, params: valid_params
      }.to change(User, :count).by(1)
    end

    it 'redirects to onboarding after sign up' do
      post user_registration_path, params: valid_params
      expect(response).to redirect_to(new_onboarding_entity_path)
    end

    context 'with invalid params (password mismatch)' do
      it 'returns unprocessable_content' do
        post user_registration_path, params: {
          user: valid_params[:user].merge(password_confirmation: 'wrong')
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
