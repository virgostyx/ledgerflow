require 'rails_helper'

RSpec.describe 'Accounting::IntracomListings', type: :request do
  include_context 'with_open_fiscal_year'

  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)    { create(:user, role: :manager) }

  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager,    user: manager,    entity: entity) }

  before { sign_in accountant }

  describe 'GET /accounting/intracom_listings' do
    it 'retourne 200' do
      get accounting_intracom_listings_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounting/intracom_listings/new' do
    it 'retourne 200' do
      get new_accounting_intracom_listing_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /accounting/intracom_listings' do
    let(:valid_params) do
      {
        accounting_intracom_listing: {
          fiscal_year_id: fiscal_year.id,
          period_start:   Date.new(2025, 1, 1).iso8601,
          period_end:     Date.new(2025, 3, 31).iso8601
        }
      }
    end

    it 'crée un relevé intracommunautaire' do
      expect {
        post accounting_intracom_listings_path, params: valid_params
      }.to change(Accounting::IntracomListing, :count).by(1)
    end

    it 'redirige vers le relevé créé' do
      post accounting_intracom_listings_path, params: valid_params
      expect(response).to redirect_to(accounting_intracom_listing_path(Accounting::IntracomListing.last))
    end

    it 'retourne 422 sans période' do
      post accounting_intracom_listings_path, params: {
        accounting_intracom_listing: { fiscal_year_id: fiscal_year.id }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'retourne 422 si period_end < period_start' do
      post accounting_intracom_listings_path, params: {
        accounting_intracom_listing: {
          fiscal_year_id: fiscal_year.id,
          period_start:   Date.new(2025, 3, 31).iso8601,
          period_end:     Date.new(2025, 1, 1).iso8601
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'GET /accounting/intracom_listings/:id' do
    let(:listing) { create(:intracom_listing, fiscal_year: fiscal_year) }

    it 'retourne 200' do
      get accounting_intracom_listing_path(listing)
      expect(response).to have_http_status(:ok)
    end

    it 'affiche les lignes du relevé (partenaire, code, montant)' do
      partner = create(:partner, vat_number: 'FR32123456789', country: 'FR')
      create(:intracom_listing_line, intracom_listing: listing, partner: partner, code: 'L', amount: '1000.00')
      get accounting_intracom_listing_path(listing)
      expect(response.body).to include(partner.name)
      expect(response.body).to match(/1[\s,.]?000[.,]00/)
    end
  end

  describe 'accès manager' do
    before { sign_in manager }

    it 'GET index retourne 200' do
      get accounting_intracom_listings_path
      expect(response).to have_http_status(:ok)
    end

    it 'POST create est refusé' do
      post accounting_intracom_listings_path, params: {
        accounting_intracom_listing: { fiscal_year_id: fiscal_year.id }
      }
      expect(response).to redirect_to(accounting_root_path)
    end
  end
end
