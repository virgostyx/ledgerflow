require 'rails_helper'

RSpec.describe Accounting::MoneyDisplayComponent, type: :component do
  it 'affiche le montant formaté' do
    render_inline(described_class.new(amount: BigDecimal('1234.56')))
    expect(page).to have_text('1 234,56 €')
  end

  it 'applique text-emerald-600 pour un montant positif' do
    render_inline(described_class.new(amount: BigDecimal('100')))
    expect(page).to have_css('.text-emerald-600')
  end

  it 'applique text-red-600 pour un montant négatif' do
    render_inline(described_class.new(amount: BigDecimal('-100')))
    expect(page).to have_css('.text-red-600')
  end

  it 'applique text-gray-500 pour zéro' do
    render_inline(described_class.new(amount: BigDecimal('0')))
    expect(page).to have_css('.text-gray-500')
  end

  it 'affiche le format signé quand show_sign: true' do
    render_inline(described_class.new(amount: BigDecimal('500'), show_sign: true))
    expect(page).to have_text('+500,00 €')
  end
end
