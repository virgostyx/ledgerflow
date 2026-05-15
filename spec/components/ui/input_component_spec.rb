require 'rails_helper'

RSpec.describe Ui::InputComponent, type: :component do
  it 'renders an input with a label' do
    render_inline(described_class.new(name: 'amount', label: 'Montant'))
    expect(page).to have_css('label', text: 'Montant')
    expect(page).to have_css('input[name="amount"]')
  end

  it 'renders the placeholder' do
    render_inline(described_class.new(name: 'email', label: 'Email', placeholder: 'user@example.com'))
    expect(page).to have_css('input[placeholder="user@example.com"]')
  end

  it 'renders with a value' do
    render_inline(described_class.new(name: 'amount', label: 'Montant', value: '1000.00'))
    expect(page).to have_css('input[value="1000.00"]')
  end

  it 'renders as required' do
    render_inline(described_class.new(name: 'email', label: 'Email', required: true))
    expect(page).to have_css('input[required]')
  end

  it 'renders an error state' do
    render_inline(described_class.new(name: 'amount', label: 'Montant', error: 'Champ requis'))
    expect(page).to have_css('input.border-red-500')
    expect(page).to have_css('.text-red-600', text: 'Champ requis')
  end

  it 'renders as disabled' do
    render_inline(described_class.new(name: 'ref', label: 'Référence', disabled: true))
    expect(page).to have_css('input[disabled]')
  end
end
