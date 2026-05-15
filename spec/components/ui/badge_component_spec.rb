require 'rails_helper'

RSpec.describe Ui::BadgeComponent, type: :component do
  it 'renders with default variant' do
    render_inline(described_class.new(label: 'Brouillon'))
    expect(page).to have_css('span.bg-gray-100', text: 'Brouillon')
  end

  it 'renders with success variant' do
    render_inline(described_class.new(label: 'Validé', variant: :success))
    expect(page).to have_css('span.bg-emerald-100', text: 'Validé')
  end

  it 'renders with warning variant' do
    render_inline(described_class.new(label: 'Brouillon', variant: :warning))
    expect(page).to have_css('span.bg-amber-100', text: 'Brouillon')
  end

  it 'renders with danger variant' do
    render_inline(described_class.new(label: 'Erreur', variant: :danger))
    expect(page).to have_css('span.bg-red-100', text: 'Erreur')
  end

  it 'renders with primary variant' do
    render_inline(described_class.new(label: 'Info', variant: :primary))
    expect(page).to have_css('span.bg-indigo-100', text: 'Info')
  end

  it 'raises on unknown variant' do
    expect { described_class.new(label: 'X', variant: :unknown) }
      .to raise_error(ArgumentError)
  end
end
