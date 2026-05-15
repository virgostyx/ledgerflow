require 'rails_helper'

RSpec.describe 'Workflow : Création et validation d une écriture', type: :system, js: true do
  include_context 'with_open_fiscal_year'

  let!(:purchase_journal) { create(:journal, :purchase) }
  let!(:account_604) { create(:account, code: '604000', label_fr: 'Services divers') }
  let!(:account_440) { create(:account, code: '440000', label_fr: 'Fournisseurs') }
  let!(:account_411) { create(:account, code: '411000', label_fr: 'TVA à récupérer') }
  let(:accountant)   { create(:user, role: :accountant) }

  before { login_as accountant, scope: :user }

  it 'permet à un comptable de créer et valider une écriture équilibrée' do
    visit new_accounting_journal_entry_path

    select 'ACH — Achats', from: 'Journal'
    execute_script("document.querySelector('input[type=\"date\"]').value = '#{Date.current.iso8601}'")
    fill_in 'Description', with: 'Achat fournitures bureau'

    within '[data-controller="journal-entry-form"]' do
      within '.entry-lines', match: :first do
        execute_script(
          "document.querySelector('[name=\"accounting_journal_entry[lines_attributes][0][account_id]\"]').value = '#{account_604.id}'"
        )
        fill_in 'Débit', with: '1210.00'
      end

      click_button 'Ajouter une ligne'
      expect(page).to have_css('.entry-lines', count: 2)

      execute_script(
        "document.querySelectorAll('.entry-lines')[1].querySelector('[name*=\"account_id\"]').value = '#{account_440.id}'"
      )
      within all('.entry-lines').last do
        fill_in 'Crédit', with: '1210.00'
      end
    end

    expect(page).to have_css('.balance-indicator .bg-emerald-100', text: 'Équilibré')
    expect(page).to have_button('Valider', disabled: false)

    click_button 'Valider'

    expect(page).to have_css('.bg-emerald-100', text: 'Validé')
    expect(page).not_to have_button('Modifier')
  end

  it 'désactive le bouton Valider quand l écriture est déséquilibrée' do
    visit new_accounting_journal_entry_path

    within '[data-controller="journal-entry-form"]' do
      within '.entry-lines', match: :first do
        fill_in 'Débit', with: '500.00'
      end
    end

    expect(page).to have_css('.balance-indicator .bg-red-100', text: 'Déséquilibré')
    expect(page).to have_button('Valider', disabled: true)
  end
end
