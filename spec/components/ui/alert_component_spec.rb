require 'rails_helper'

RSpec.describe Ui::AlertComponent, type: :component do
  it 'renders an info alert' do
    render_inline(described_class.new(message: 'Information', variant: :info))
    expect(page).to have_css('.bg-indigo-50', text: 'Information')
  end

  it 'renders a success alert' do
    render_inline(described_class.new(message: 'Enregistré', variant: :success))
    expect(page).to have_css('.bg-emerald-50', text: 'Enregistré')
  end

  it 'renders a warning alert' do
    render_inline(described_class.new(message: 'Attention', variant: :warning))
    expect(page).to have_css('.bg-amber-50', text: 'Attention')
  end

  it 'renders a danger alert' do
    render_inline(described_class.new(message: 'Erreur critique', variant: :danger))
    expect(page).to have_css('.bg-red-50', text: 'Erreur critique')
  end

  it 'renders with a title' do
    render_inline(described_class.new(message: 'Détail', title: 'Titre alerte', variant: :info))
    expect(page).to have_css('.font-semibold', text: 'Titre alerte')
  end
end
