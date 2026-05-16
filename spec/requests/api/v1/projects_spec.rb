require 'rails_helper'

RSpec.describe 'Api::V1::Projects', type: :request do
  include_context 'with_authenticated_api'
  include_context 'with_open_fiscal_year'

  describe 'GET /api/v1/projects/:id/accounting_summary' do
    it_behaves_like 'a JWT-protected endpoint' do
      subject { get '/api/v1/projects/42/accounting_summary', headers: {} }
    end

    context 'avec token valide' do
      let!(:journal)  { create(:journal, :purchase) }
      let!(:account_604) { create(:account, code: '604000', label_fr: 'Charges',
                                  account_type: :expense, normal_balance: :debit) }
      let!(:account_700) { create(:account, code: '700000', label_fr: 'Ventes',
                                  account_type: :revenue, normal_balance: :credit) }

      before do
        entry = create(:journal_entry, :draft, journal: journal,
                       fiscal_year: fiscal_year, project_id: 42)
        ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
        create(:journal_entry_line, journal_entry: entry, account: account_604,
               debit: BigDecimal('5000.00'), credit: BigDecimal('0'))
        create(:journal_entry_line, journal_entry: entry, account: account_700,
               debit: BigDecimal('0'), credit: BigDecimal('5000.00'))
        entry.post!
      end

      it 'retourne 200' do
        get '/api/v1/projects/42/accounting_summary', headers: auth_headers
        expect(response).to have_http_status(:ok)
      end

      it 'retourne les agrégats comptables' do
        get '/api/v1/projects/42/accounting_summary', headers: auth_headers
        body = JSON.parse(response.body)
        expect(body).to include('charges', 'produits', 'solde')
        expect(body['charges'].to_f).to eq(5000.0)
      end

      it 'retourne 0 pour un projet sans écritures' do
        get '/api/v1/projects/999/accounting_summary', headers: auth_headers
        body = JSON.parse(response.body)
        expect(body['charges'].to_f).to eq(0.0)
        expect(body['produits'].to_f).to eq(0.0)
      end
    end
  end
end
