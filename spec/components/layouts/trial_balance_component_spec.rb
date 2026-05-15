require 'rails_helper'

RSpec.describe Layouts::TrialBalanceComponent, type: :component do
  let(:rows) do
    [
      { code: '400000', label: 'Clients',        debit: BigDecimal('5000.00'), credit: BigDecimal('0') },
      { code: '440000', label: 'Fournisseurs',   debit: BigDecimal('0'),       credit: BigDecimal('3000.00') },
      { code: '700000', label: 'Ventes',         debit: BigDecimal('0'),       credit: BigDecimal('2000.00') }
    ]
  end

  before { render_inline(described_class.new(rows: rows, fiscal_year_label: 'Ex. 2026')) }

  it 'affiche le titre avec l exercice' do
    expect(page).to have_text('Ex. 2026')
  end

  it 'affiche les codes et libellés de comptes' do
    expect(page).to have_text('400000')
    expect(page).to have_text('Clients')
  end

  it 'affiche les montants débit et crédit' do
    expect(page).to have_text('5 000,00 €')
    expect(page).to have_text('3 000,00 €')
  end

  it 'affiche un tableau de balance' do
    expect(page).to have_css('table')
  end
end
