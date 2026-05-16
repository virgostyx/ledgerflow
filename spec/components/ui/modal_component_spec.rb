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
    expect(page).to have_css('button[aria-label="Close"]')
  end

  it 'has a dialog role' do
    render_inline(described_class.new(title: 'Titre')) { 'Corps' }
    expect(page).to have_css('[role="dialog"]')
  end

  it 'has data-controller modal' do
    render_inline(described_class.new(title: 'Titre')) { 'Corps' }
    expect(page).to have_css('[data-controller="modal"]')
  end

  it 'closes on backdrop click' do
    render_inline(described_class.new(title: 'Titre')) { 'Corps' }
    expect(page).to have_css('[data-action*="modal#close"]')
  end

  it 'closes on Esc key' do
    render_inline(described_class.new(title: 'Titre')) { 'Corps' }
    expect(page).to have_css('[data-action*="keydown.esc@window->modal#close"]')
  end

  it 'renders a footer slot' do
    render_inline(described_class.new(title: 'Titre')) do |c|
      c.with_footer { 'Modal footer' }
      'Corps'
    end
    expect(page).to have_text('Modal footer')
    expect(page.find('.border-t')).to have_text('Modal footer')
  end

  it 'aligns near top with align: :top' do
    render_inline(described_class.new(title: 'Titre', align: :top)) { 'Corps' }
    expect(page).to have_css('.items-start')
  end

  it 'centers by default' do
    render_inline(described_class.new(title: 'Titre')) { 'Corps' }
    expect(page).to have_css('.items-center')
  end
end
