require 'rails_helper'

RSpec.describe 'Entities', type: :request do
  include_context 'with entity'

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :admin, user: user, entity: entity) }

  before { sign_in user }

  describe 'GET /entities' do
    it 'returns 200' do
      get entities_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /entities/new' do
    it 'returns 200' do
      get new_entity_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /entities' do
    let(:valid_params) do
      {
        entity: {
          name:       'Deuxieme Entite',
          legal_name: 'Deuxieme Entite SA',
          legal_form: 'SA',
          country:    'BE'
        }
      }
    end

    it 'creates a new entity' do
      expect {
        post entities_path, params: valid_params
      }.to change(Entity, :count).by(1)
    end

    it 'redirects to the accounting dashboard' do
      post entities_path, params: valid_params
      expect(response).to redirect_to(accounting_root_path)
    end

    context 'with invalid params' do
      it 'returns unprocessable_content' do
        post entities_path, params: { entity: { name: '', legal_name: 'Test', country: 'BE' } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when provisioning fails' do
      before do
        allow(Entities::ProvisionEntity).to receive(:call).and_return(
          double('result', success?: false, failure?: true)
        )
      end

      it 'destroys the entity and re-renders the form' do
        expect {
          post entities_path, params: valid_params
        }.not_to change(Entity, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'POST /entities/:id/switch' do
    let(:other_entity) { create(:entity, created_by: user) }
    let!(:other_membership) { create(:user_entity, :accountant, user: user, entity: other_entity) }

    it 'updates current_entity_id in session and redirects to dashboard' do
      post switch_entity_path(other_entity)
      expect(response).to redirect_to(accounting_root_path)
      follow_redirect!
      expect(session[:current_entity_id]).to eq(other_entity.id)
    end

    it 'redirects to entities list when entity not found' do
      post switch_entity_path(0)
      expect(response).to redirect_to(entities_path)
    end
  end
end
