require 'rails_helper'

RSpec.describe Ui::CalculatorComponent, type: :component do
  before { render_inline(described_class.new) }

  it 'has the calculator data controller' do
    expect(page).to have_css('[data-controller="calculator"]')
  end

  it 'renders the FAB toggle button' do
    expect(page).to have_css('[data-action*="calculator#toggle"]')
  end

  it 'panel is hidden by default' do
    expect(page).to have_css('[data-calculator-target="panel"].hidden')
  end

  it 'renders digit buttons 0–9' do
    (0..9).each do |digit|
      expect(page).to have_css("[data-calc-value='#{digit}']")
    end
  end

  it 'renders operation buttons' do
    %w[+ - * /].each do |op|
      expect(page).to have_css("[data-calc-op='#{op}']")
    end
  end

  it 'has a display target' do
    expect(page).to have_css('[data-calculator-target="display"]')
  end

  it 'has an expression target' do
    expect(page).to have_css('[data-calculator-target="expression"]')
  end

  it 'has an equals button' do
    expect(page).to have_css('[data-action*="calculator#equals"]')
  end

  it 'has a copy button' do
    expect(page).to have_css('[data-action*="calculator#copy"]')
  end

  it 'has a clear button' do
    expect(page).to have_css('[data-action*="calculator#reset"]')
  end
end
