require 'rails_helper'

RSpec.describe 'Account autocomplete on the invoice form', type: :system, js: true do
  include_context 'with_open_fiscal_year'

  let!(:account_700) { create(:account, code: '700000', label_fr: 'Ventes de marchandises', is_leaf: true) }
  let!(:account_170) { create(:account, code: '170100', label_fr: 'Emprunts', is_leaf: true) }
  let!(:account_550) { create(:account, code: '550000', label_fr: 'Banque', is_leaf: true) }
  let(:accountant)   { create(:user, role: :accountant) }
  let!(:membership)  { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before do
    login_as accountant, scope: :user
    visit accounting_new_sales_path
  end

  def type_in_account_field(text)
    find('input[placeholder="Account…"]', match: :first).fill_in(with: text)
  end

  it 'matches codes by prefix only' do
    type_in_account_field('7')

    expect(page).to have_css('[data-account-search-target="suggestions"] div', text: '700000')
    expect(page).not_to have_css('[data-account-search-target="suggestions"] div', text: '170100')
  end

  it 'still searches labels for non-numeric input' do
    type_in_account_field('banque')

    expect(page).to have_css('[data-account-search-target="suggestions"] div', text: '550000')
  end
end
