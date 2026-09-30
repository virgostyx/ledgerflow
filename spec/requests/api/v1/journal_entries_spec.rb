require 'rails_helper'

RSpec.describe 'Api::V1::JournalEntries', type: :request do
  include_context 'with_authenticated_api'
  include_context 'with_open_fiscal_year'
  let(:entity) { create(:entity, budgetflow_enabled: true) } # the API only exists for entities that declared BudgetFlow

  let!(:default_account) { create(:account, code: '440000', label_fr: 'Fournisseurs',
                                  account_type: :liability, normal_balance: :credit) }
  let!(:purchase_journal) { create(:journal, :purchase, default_account: default_account) }
  let!(:account_604)      { create(:account, code: '604000', label_fr: 'Services divers',
                                   account_type: :expense, normal_balance: :debit) }

  describe 'POST /api/v1/journal_entries' do
    it 'no longer exists: third parties inject invoices, not ad-hoc entries' do
      expect {
        post '/api/v1/journal_entries', params: { account_code: '604000', amount: '100', date: Date.current.iso8601 },
                                        headers: auth_headers
      }.not_to change(Accounting::JournalEntry, :count)

      expect(response).to have_http_status(:not_found)
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
