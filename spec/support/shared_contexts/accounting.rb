RSpec.shared_context 'with_open_fiscal_year' do
  include_context 'with entity'
  let!(:fiscal_year) { create(:fiscal_year, status: :open, entity: entity) }
end

RSpec.shared_context 'with_pcmn_accounts' do
  include_context 'with entity'
  let!(:account_604) { create(:account, code: '604000', label_fr: 'Services divers', entity: entity) }
  let!(:account_440) { create(:account, code: '440000', label_fr: 'Fournisseurs', reconcilable: true, entity: entity) }
  let!(:account_400) { create(:account, code: '400000', label_fr: 'Clients', reconcilable: true, entity: entity) }
  let!(:account_411) { create(:account, code: '410100', label_fr: 'TVA à récupérer', entity: entity) }
  let!(:account_700) { create(:account, code: '700000', label_fr: 'Ventes', entity: entity) }
  let!(:account_451) { create(:account, code: '450100', label_fr: 'TVA à reverser', entity: entity) }
  let!(:account_550) { create(:account, code: '550000', label_fr: 'ING Compte courant', account_class: 5, entity: entity) }
  let!(:account_570) { create(:account, code: '570000', label_fr: 'Caisse principale', account_class: 5, entity: entity) }
  let!(:account_651200) { create(:account, code: '651200', label_fr: 'Différences de change', account_class: 6, entity: entity) }
  let!(:account_751100) { create(:account, code: '751100', label_fr: 'Gains de change', account_class: 7, entity: entity) }
  let!(:account_640400) { create(:account, code: '640400', label_fr: 'TVA non déductible', account_class: 6, entity: entity) }
end

RSpec.shared_context 'with_authenticated_api' do
  let(:entity)       { create(:entity) }
  let(:jwt_token)    { Api::JwtService.encode({ client: 'budgetflow', entity_id: entity.id }) }
  let(:auth_headers) { { 'Authorization' => "Bearer #{jwt_token}" } }
end
