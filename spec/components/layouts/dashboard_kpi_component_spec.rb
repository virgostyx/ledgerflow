require 'rails_helper'

RSpec.describe Layouts::DashboardKpiComponent, type: :component do
  let(:kpis) do
    [
      { label: 'Factures à valider', value: 5,                  icon: 'document-text' },
      { label: 'Solde trésorerie',   value: '12 345,00 €',      icon: 'banknotes' },
      { label: 'Écritures brouillon', value: 3,                 icon: 'book-open' }
    ]
  end

  before { render_inline(described_class.new(kpis: kpis)) }

  it 'affiche le label de chaque KPI' do
    expect(page).to have_text('Factures à valider')
    expect(page).to have_text('Solde trésorerie')
  end

  it 'affiche les valeurs' do
    expect(page).to have_text('5')
    expect(page).to have_text('12 345,00 €')
  end

  it 'affiche une grille de KPIs' do
    expect(page).to have_css('.kpi-grid')
  end
end
