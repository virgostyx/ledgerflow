require 'rails_helper'

RSpec.describe 'Onboarding::Entities', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /onboarding/entity/new' do
    it 'returns 200' do
      get new_onboarding_entity_path
      expect(response).to have_http_status(:ok)
    end

    it 'redirects to sign in when unauthenticated' do
      sign_out user
      get new_onboarding_entity_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'POST /onboarding/entity' do
    let(:valid_params) do
      {
        entity: {
          name:       'Ma ASBL Test',
          legal_name: 'Ma ASBL Test',
          legal_form: 'ASBL',
          country:    'BE'
        }
      }
    end

    context 'with valid params' do
      it 'creates an entity' do
        expect {
          post onboarding_entity_path, params: valid_params
        }.to change(Entity, :count).by(1)
      end

      it 'redirects to the accounting dashboard' do
        post onboarding_entity_path, params: valid_params
        expect(response).to redirect_to(accounting_root_path)
      end

      it 'stores the new entity id in session' do
        post onboarding_entity_path, params: valid_params
        expect(session[:current_entity_id]).to eq(Entity.last.id)
      end

      it 'provisions the entity with PCMN accounts' do
        post onboarding_entity_path, params: valid_params
        entity = Entity.last
        count = ActsAsTenant.with_tenant(entity) { Accounting::Account.count }
        expect(count).to be >= 200
      end
    end

    context 'with invalid params (blank name)' do
      it 'returns unprocessable_content' do
        post onboarding_entity_path, params: { entity: { name: '', legal_name: 'Test', country: 'BE' } }
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
          post onboarding_entity_path, params: valid_params
        }.not_to change(Entity, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
