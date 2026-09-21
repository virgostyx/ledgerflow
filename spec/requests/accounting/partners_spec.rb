require 'rails_helper'

RSpec.describe 'Accounting::Partners', type: :request do
  include_context 'with entity'

  let(:accountant) { create(:user, role: :accountant) }
  let(:admin)      { create(:user, role: :admin) }

  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:admin_membership)      { create(:user_entity, :admin,      user: admin,      entity: entity) }

  before { sign_in accountant }

  describe 'GET /accounting/partners' do
    it 'retourne 200' do
      get accounting_partners_path
      expect(response).to have_http_status(:ok)
    end

    it 'pagine la liste' do
      create_list(:partner, 26)
      get accounting_partners_path
      expect(response.body.scan('View</a>').size).to eq(25)
      get accounting_partners_path, params: { page: 2 }
      expect(response.body.scan('View</a>').size).to eq(1)
    end

    describe 'filtres' do
      let!(:acme)   { create(:partner, name: 'ZZAcme', partner_type: :customer, country: 'BE', city: 'Namur') }
      let!(:globex) { create(:partner, name: 'ZZGlobex', partner_type: :supplier, country: 'FR', city: 'Lyon') }
      let!(:gone)   { create(:partner, name: 'ZZGone', active: false) }

      it 'filtre par nom ou ville' do
        get accounting_partners_path, params: { q: { q: 'lyon' } }
        expect(response.body).to include('ZZGlobex').and not_include('ZZAcme')
      end

      it 'filtre par type' do
        get accounting_partners_path, params: { q: { partner_type: 'customer' } }
        expect(response.body).to include('ZZAcme').and not_include('ZZGlobex')
      end

      it 'filtre par pays' do
        get accounting_partners_path, params: { q: { country: 'FR' } }
        expect(response.body).to include('ZZGlobex').and not_include('ZZAcme')
      end

      it 'masque les inactifs par défaut et les montre à la demande' do
        get accounting_partners_path
        expect(response.body).not_to include('ZZGone')
        get accounting_partners_path, params: { q: { inactive: '1' } }
        expect(response.body).to include('ZZGone')
      end
    end
  end

  describe 'GET /accounting/partners with column filters' do
    let!(:belgian) { create(:partner, :supplier, name: 'ZZBelge', country: 'BE') }
    let!(:dutch) { create(:partner, :customer, name: 'ZZDutch', country: 'NL') }

    it 'filters on country list and type' do
      get accounting_partners_path, params: { f: { country: %w[NL] } }
      expect(response.body).to include('ZZDutch').and not_include('ZZBelge')
      get accounting_partners_path, params: { f: { partner_type: %w[supplier] } }
      expect(response.body).to include('ZZBelge').and not_include('ZZDutch')
    end

    it 'sorts by name' do
      get accounting_partners_path, params: { sort: 'name', dir: 'desc' }
      expect(response.body.index('ZZDutch')).to be < response.body.index('ZZBelge')
    end

    it 'keeps Search and Include inactive but drops the redundant type and country selects' do
      get accounting_partners_path
      expect(response.body).to include('name="q[q]"', 'name="q[inactive]"')
      expect(response.body).not_to include('name="q[partner_type]"', 'name="q[country]"')
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
