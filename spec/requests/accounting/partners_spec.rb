require 'rails_helper'

RSpec.describe 'Accounting::Partners', type: :request do
  let(:accountant) { create(:user, role: :accountant) }
  let(:admin)      { create(:user, role: :admin) }

  before { sign_in accountant }

  describe 'GET /accounting/partners' do
    it 'retourne 200' do
      get accounting_partners_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounting/partners/new' do
    it 'retourne 200' do
      get new_accounting_partner_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /accounting/partners' do
    context 'avec des attributs valides' do
      let(:valid_attrs) { { name: 'ACME SA', partner_type: 'customer', country: 'BE' } }

      it 'crée un partenaire' do
        expect {
          post accounting_partners_path, params: { accounting_partner: valid_attrs }
        }.to change(Accounting::Partner, :count).by(1)
      end

      it 'redirige vers la liste' do
        post accounting_partners_path, params: { accounting_partner: valid_attrs }
        expect(response).to redirect_to(accounting_partners_path)
      end
    end

    context 'avec un numéro TVA invalide' do
      let(:invalid_attrs) { { name: 'ACME', partner_type: 'customer', vat_number: 'INVALID' } }

      it 'retourne 422 et ré-affiche le formulaire' do
        post accounting_partners_path, params: { accounting_partner: invalid_attrs }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'sans nom' do
      it 'retourne 422' do
        post accounting_partners_path, params: { accounting_partner: { name: '', partner_type: 'customer' } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'GET /accounting/partners/:id' do
    let(:partner) { create(:partner) }

    it 'retourne 200' do
      get accounting_partner_path(partner)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounting/partners/:id/edit' do
    let(:partner) { create(:partner) }

    it 'retourne 200' do
      get edit_accounting_partner_path(partner)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /accounting/partners/:id' do
    let(:partner) { create(:partner) }

    context 'avec des attributs valides' do
      it 'met à jour le partenaire et redirige' do
        patch accounting_partner_path(partner), params: {
          accounting_partner: { name: 'Nouveau Nom' }
        }
        expect(partner.reload.name).to eq('Nouveau Nom')
        expect(response).to redirect_to(accounting_partner_path(partner))
      end
    end

    context 'avec un numéro TVA invalide' do
      it 'retourne 422' do
        patch accounting_partner_path(partner), params: {
          accounting_partner: { vat_number: 'BAD' }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'DELETE /accounting/partners/:id' do
    let!(:partner) { create(:partner) }

    context 'en tant qu admin' do
      before { sign_in admin }

      it 'supprime le partenaire et redirige' do
        expect {
          delete accounting_partner_path(partner)
        }.to change(Accounting::Partner, :count).by(-1)
        expect(response).to redirect_to(accounting_partners_path)
      end
    end

    context 'en tant que comptable' do
      it 'refuse et redirige (403)' do
        delete accounting_partner_path(partner)
        expect(response).to redirect_to(accounting_root_path)
      end
    end
  end
end
