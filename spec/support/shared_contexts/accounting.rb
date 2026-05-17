RSpec.shared_context 'with_open_fiscal_year' do
  let!(:fiscal_year) { create(:fiscal_year, status: :open) }
end

RSpec.shared_context 'with_pcmn_accounts' do
  let!(:account_604) { create(:account, code: '604000', label_fr: 'Services divers') }
  let!(:account_440) { create(:account, code: '440000', label_fr: 'Fournisseurs') }
  let!(:account_400) { create(:account, code: '400000', label_fr: 'Clients') }
  let!(:account_411) { create(:account, code: '411000', label_fr: 'TVA à récupérer') }
  let!(:account_700) { create(:account, code: '700000', label_fr: 'Ventes') }
  let!(:account_451) { create(:account, code: '451000', label_fr: 'TVA à reverser') }
  let!(:account_550) { create(:account, code: '550000', label_fr: 'ING Compte courant', account_class: 5) }
  let!(:account_570) { create(:account, code: '570000', label_fr: 'Caisse principale', account_class: 5) }
end

RSpec.shared_context 'with_authenticated_api' do
  let(:jwt_token)    { Api::JwtService.encode({ client: 'budgetflow' }) }
  let(:auth_headers) { { 'Authorization' => "Bearer #{jwt_token}" } }
end
