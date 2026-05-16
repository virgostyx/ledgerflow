require 'rails_helper'

RSpec.describe Ui::CardComponent, type: :component do
  it 'renders a card with content' do
    render_inline(described_class.new) { 'Contenu de la carte' }
    expect(page).to have_css('.bg-white.rounded-xl', text: 'Contenu de la carte')
  end

  it 'renders with a title' do
    render_inline(described_class.new(title: 'Mon titre')) { 'Corps' }
    expect(page).to have_css('.text-lg.font-semibold', text: 'Mon titre')
  end

  it 'renders with a subtitle' do
    render_inline(described_class.new(title: 'Titre', subtitle: 'Sous-titre')) { 'Corps' }
    expect(page).to have_css('.text-sm.text-gray-500', text: 'Sous-titre')
  end

  it 'renders without shadow when flat' do
    render_inline(described_class.new(flat: true)) { 'Corps' }
    expect(page).not_to have_css('.shadow-sm')
  end

  it 'renders a header slot above the content' do
    render_inline(described_class.new) do |c|
      c.with_header { 'Card header' }
      'Card body'
    end
    expect(page).to have_text('Card header')
    expect(page).to have_text('Card body')
    expect(page.find('.border-b')).to have_text('Card header')
  end

  it 'renders a footer slot below the content' do
    render_inline(described_class.new) do |c|
      c.with_footer { 'Card footer' }
      'Card body'
    end
    expect(page).to have_text('Card footer')
    expect(page.find('.border-t')).to have_text('Card footer')
  end

  it 'renders without shadow when shadow: false' do
    render_inline(described_class.new(shadow: false)) { 'Corps' }
    expect(page).not_to have_css('.shadow-sm')
  end
end
