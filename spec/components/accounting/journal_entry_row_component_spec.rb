require 'rails_helper'

RSpec.describe Accounting::JournalEntryRowComponent, type: :component do
  include_context 'with_open_fiscal_year'

  let(:entry) do
    create(:journal_entry, fiscal_year: fiscal_year,
           entry_date: Date.new(2026, 3, 15),
           description: 'Achat fournitures')
  end

  it 'affiche la référence de l écriture' do
    render_inline(described_class.new(entry: entry))
    expect(page).to have_text(entry.reference)
  end

  it 'affiche la date en format belge dd/mm/yyyy' do
    render_inline(described_class.new(entry: entry))
    expect(page).to have_text('15/03/2026')
  end

  it 'affiche la description' do
    render_inline(described_class.new(entry: entry))
    expect(page).to have_text('Achat fournitures')
  end

  it 'affiche le badge de statut' do
    render_inline(described_class.new(entry: entry))
    expect(page).to have_text('Brouillon')
  end
end
