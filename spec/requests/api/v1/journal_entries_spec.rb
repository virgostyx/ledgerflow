require 'rails_helper'

RSpec.describe 'Api::V1::JournalEntries', type: :request do
  include_context 'with_authenticated_api'
  include_context 'with_open_fiscal_year'

  let!(:default_account) { create(:account, code: '440000', label_fr: 'Fournisseurs',
                                  account_type: :liability, normal_balance: :credit) }
  let!(:purchase_journal) { create(:journal, :purchase, default_account: default_account) }
  let!(:account_604)      { create(:account, code: '604000', label_fr: 'Services divers',
                                   account_type: :expense, normal_balance: :debit) }

  describe 'POST /api/v1/journal_entries' do
    it_behaves_like 'a JWT-protected endpoint' do
      subject { post '/api/v1/journal_entries', headers: {} }
    end

    context 'avec token valide' do
      let(:params) do
        { project_id: 42, amount: '1000.00', date: Date.current.iso8601,
          description: 'Mission terrain', account_code: '604000' }
      end

      it 'crée une écriture comptable' do
        expect {
          post '/api/v1/journal_entries', params: params, headers: auth_headers
        }.to change(Accounting::JournalEntry, :count).by(1)
      end

      it 'retourne 201 avec la référence' do
        post '/api/v1/journal_entries', params: params, headers: auth_headers
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body['reference']).to match(/ACH\d{4}\/\d{4}/)
        expect(body['status']).to eq('posted')
      end

      it 'stocke le project_id sur l écriture' do
        post '/api/v1/journal_entries', params: params, headers: auth_headers
        expect(Accounting::JournalEntry.last.project_id).to eq(42)
      end
    end

    context 'avec compte inconnu' do
      it 'retourne 422' do
        post '/api/v1/journal_entries',
             params: { account_code: 'XXXXX', amount: '100', date: Date.current.iso8601 },
             headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'GET /api/v1/journal_entries' do
    it_behaves_like 'a JWT-protected endpoint' do
      subject { get '/api/v1/journal_entries', headers: {} }
    end

    context 'avec token valide' do
      let!(:entry) { create(:journal_entry, :posted, fiscal_year: fiscal_year,
                             journal: purchase_journal, project_id: 42) }

      it 'retourne 200 avec les écritures' do
        get '/api/v1/journal_entries', headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to be_an(Array)
      end

      it 'filtre par project_id' do
        get '/api/v1/journal_entries', params: { project_id: 42 }, headers: auth_headers
        ids = JSON.parse(response.body).map { |e| e['id'] }
        expect(ids).to include(entry.id)
      end
    end
  end

  describe 'GET /api/v1/journal_entries/:id' do
    it_behaves_like 'a JWT-protected endpoint' do
      subject { get '/api/v1/journal_entries/1', headers: {} }
    end

    context 'avec token valide' do
      let!(:entry) { create(:journal_entry, :posted, fiscal_year: fiscal_year,
                             journal: purchase_journal) }

      it 'retourne 200 avec l écriture' do
        get "/api/v1/journal_entries/#{entry.id}", headers: auth_headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['id']).to eq(entry.id)
      end
    end
  end
end
