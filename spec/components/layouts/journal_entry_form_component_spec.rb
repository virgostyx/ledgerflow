require 'rails_helper'

RSpec.describe Layouts::JournalEntryFormComponent, type: :component do
  include_context 'with_open_fiscal_year'

  let(:journals) { [ create(:journal, :purchase), create(:journal, :sale) ] }
  let(:accounts) { [ create(:account, code: '604000', label_fr: 'Services divers') ] }
  let(:entry)    { build(:journal_entry, journal: journals.first, fiscal_year: fiscal_year) }

  before { render_inline(described_class.new(entry: entry, journals: journals, accounts: accounts)) }

  it 'a le data-controller journal-entry-form' do
    expect(page).to have_css('[data-controller="journal-entry-form"]')
  end

  it 'affiche un select pour le journal' do
    expect(page).to have_select('Journal')
  end

  it 'affiche un champ date' do
    expect(page).to have_field('Date')
  end

  it 'affiche la zone de lignes d écriture' do
    expect(page).to have_css('.entry-lines')
  end

  it 'affiche l indicateur de balance' do
    expect(page).to have_css('.balance-indicator')
  end

  it 'affiche le bouton Ajouter une ligne' do
    expect(page).to have_button('Ajouter une ligne')
  end

  it 'affiche le bouton Valider' do
    expect(page).to have_button('Valider', disabled: true)
  end

  it 'inclut un template pour les nouvelles lignes' do
    expect(page).to have_css('template', visible: :all)
  end
end
