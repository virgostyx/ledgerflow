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
    expect(page).to have_button('Add a line')
  end

  it 'affiche le bouton Valider' do
    expect(page).to have_button('Save', disabled: true)
  end

  it 'inclut un template pour les nouvelles lignes' do
    expect(page).to have_css('template', visible: :all)
  end

  context 'with analytical axes' do
    let(:axis)         { create(:analytical_axis, :proj) }
    let(:anal_account) { create(:analytical_account, analytical_axis: axis,
                                code: 'PROJ-001', label_fr: 'Project Alpha') }

    before do
      anal_account
      render_inline(described_class.new(
        entry: entry, journals: journals, accounts: accounts, axes: [ axis ]
      ))
    end

    it 'renders an axis section per line' do
      expect(page).to have_css('.analytical-axes-row')
    end

    it 'renders a select for each axis' do
      expect(page).to have_css('select[data-axis-id]')
    end

    it 'renders analytical accounts as options' do
      expect(page).to have_css('option', text: 'Project Alpha', visible: :all)
    end

    it 'includes the axes JSON on the form element' do
      expect(page).to have_css('[data-journal-entry-form-axes-value]')
    end
  end
end
