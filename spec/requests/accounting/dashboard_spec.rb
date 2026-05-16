require 'rails_helper'

RSpec.describe 'Accounting::Dashboard', type: :request do
  include_context 'with_open_fiscal_year'

  let!(:user) { create(:user, role: :accountant) }

  before { sign_in user }

  describe 'GET /accounting' do
    it 'returns 200' do
      get accounting_root_path
      expect(response).to have_http_status(:ok)
    end

    it 'shows draft invoices KPI' do
      partner = create(:partner)
      create_list(:invoice, 3, :draft, partner: partner, fiscal_year: fiscal_year)
      get accounting_root_path
      expect(response.body).to include('3')
    end

    it 'shows draft journal entries KPI' do
      journal = create(:journal)
      create_list(:journal_entry, 2, :draft, journal: journal, fiscal_year: fiscal_year)
      get accounting_root_path
      expect(response.body).to include('2')
    end

    it 'redirects to sign_in when unauthenticated' do
      sign_out user
      get accounting_root_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
