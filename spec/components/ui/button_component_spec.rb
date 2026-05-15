require 'rails_helper'

RSpec.describe Ui::ButtonComponent, type: :component do
  it 'renders a primary button with label' do
    render_inline(described_class.new(label: 'Valider'))
    expect(page).to have_css('button.bg-indigo-600', text: 'Valider')
  end

  it 'renders a secondary button' do
    render_inline(described_class.new(label: 'Annuler', variant: :secondary))
    expect(page).to have_css('button.bg-white', text: 'Annuler')
  end

  it 'renders a danger button' do
    render_inline(described_class.new(label: 'Supprimer', variant: :danger))
    expect(page).to have_css('button.bg-red-600', text: 'Supprimer')
  end

  it 'renders as disabled' do
    render_inline(described_class.new(label: 'Valider', disabled: true))
    expect(page).to have_css('button[disabled]')
  end

  it 'renders with a type attribute' do
    render_inline(described_class.new(label: 'Envoyer', type: 'submit'))
    expect(page).to have_css('button[type="submit"]')
  end

  it 'renders with additional html attributes' do
    render_inline(described_class.new(label: 'Clic', data: { action: 'click->foo#bar' }))
    expect(page).to have_css('button[data-action="click->foo#bar"]')
  end
end
