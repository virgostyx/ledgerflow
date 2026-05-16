require 'rails_helper'

RSpec.describe 'Api::V1::Invoices', type: :request do
  include_context 'with_authenticated_api'
  include_context 'with_open_fiscal_year'

  describe 'GET /api/v1/invoices' do
    it_behaves_like 'a JWT-protected endpoint' do
      subject { get '/api/v1/invoices', headers: {} }
    end

    context 'avec token valide' do
      let!(:partner)  { create(:partner) }
      let!(:journal)  { create(:journal, :sale) }
      let!(:invoice)  { create(:invoice, :draft, partner: partner, fiscal_year: fiscal_year) }

      it 'retourne 200 avec les factures' do
        get '/api/v1/invoices', headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to be_an(Array)
      end

      it 'filtre par statut' do
        get '/api/v1/invoices', params: { status: 'draft' }, headers: auth_headers
        statuses = JSON.parse(response.body).map { |i| i['status'] }
        expect(statuses).to all(eq('draft'))
      end
    end
  end

  describe 'GET /api/v1/invoices/:id' do
    it_behaves_like 'a JWT-protected endpoint' do
      subject { get '/api/v1/invoices/1', headers: {} }
    end

    context 'avec token valide' do
      let!(:partner) { create(:partner) }
      let!(:invoice) { create(:invoice, :draft, partner: partner, fiscal_year: fiscal_year) }

      it 'retourne 200 avec la facture' do
        get "/api/v1/invoices/#{invoice.id}", headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['id']).to eq(invoice.id)
      end
    end
  end
end
