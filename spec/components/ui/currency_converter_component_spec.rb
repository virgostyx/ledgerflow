require 'rails_helper'

RSpec.describe Ui::CurrencyConverterComponent, type: :component do
  before { render_inline(described_class.new) }

  it 'has the currency-converter data controller' do
    expect(page).to have_css('[data-controller="currency-converter"]')
  end

  it 'renders the FAB toggle button' do
    expect(page).to have_css('[data-action*="currency-converter#toggle"]')
  end

  it 'panel is hidden by default' do
    expect(page).to have_css('[data-currency-converter-target="panel"].hidden')
  end

  it 'renders currency options for USD, GBP, CHF, JPY' do
    %w[USD GBP CHF JPY].each do |currency|
      expect(page).to have_css("option[value='#{currency}']")
    end
  end

  it 'has an amount input' do
    expect(page).to have_css('[data-currency-converter-target="amountInput"]')
  end

  it 'has a result display' do
    expect(page).to have_css('[data-currency-converter-target="resultDisplay"]')
  end

  it 'has a swap direction button' do
    expect(page).to have_css('[data-action*="currency-converter#swapDirection"]')
  end

  it 'has a copy button' do
    expect(page).to have_css('[data-action*="currency-converter#copy"]')
  end

  it 'shows direction labels' do
    expect(page).to have_css('[data-currency-converter-target="directionFromLabel"]')
    expect(page).to have_css('[data-currency-converter-target="directionToLabel"]')
  end
end
