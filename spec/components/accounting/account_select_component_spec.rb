require 'rails_helper'

RSpec.describe Accounting::AccountSelectComponent, type: :component do
  include_context 'with entity'

  let(:accounts) do
    [
      build_stubbed(:account, id: 1, code: '604000', label_fr: 'Services divers'),
      build_stubbed(:account, id: 2, code: '440000', label_fr: 'Fournisseurs')
    ]
  end

  it 'affiche un élément select avec le bon name' do
    render_inline(described_class.new(accounts: accounts, name: 'account_id'))
    expect(page).to have_css('select[name="account_id"]')
  end

  it 'affiche toutes les options avec code et libellé' do
    render_inline(described_class.new(accounts: accounts, name: 'account_id'))
    expect(page).to have_text('604000 — Services divers')
    expect(page).to have_text('440000 — Fournisseurs')
  end

  it 'sélectionne l option correspondant au compte courant' do
    render_inline(described_class.new(accounts: accounts, name: 'account_id', selected: 1))
    expect(page).to have_css("option[value='1'][selected]")
  end

  it 'inclut une option vide quand prompt est fourni' do
    render_inline(described_class.new(accounts: accounts, name: 'account_id', prompt: 'Choisir un compte'))
    expect(page).to have_text('Choisir un compte')
  end
end
