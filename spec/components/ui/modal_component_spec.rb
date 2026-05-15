require 'rails_helper'

RSpec.describe Ui::ModalComponent, type: :component do
  it 'renders with a title' do
    render_inline(described_class.new(title: 'Confirmer')) { 'Contenu' }
    expect(page).to have_css('.font-semibold', text: 'Confirmer')
  end

  it 'renders the body content' do
    render_inline(described_class.new(title: 'Titre')) { 'Corps du modal' }
    expect(page).to have_text('Corps du modal')
  end

  it 'renders a close button' do
    render_inline(described_class.new(title: 'Titre')) { 'Corps' }
    expect(page).to have_css('button[aria-label="Fermer"]')
  end

  it 'has a dialog role' do
    render_inline(described_class.new(title: 'Titre')) { 'Corps' }
    expect(page).to have_css('[role="dialog"]')
  end
end
