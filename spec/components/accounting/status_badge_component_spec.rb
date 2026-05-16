require 'rails_helper'

RSpec.describe Accounting::StatusBadgeComponent, type: :component do
  it 'affiche un badge brouillon' do
    render_inline(described_class.new(status: :draft))
    expect(page).to have_text('Draft')
    expect(page).to have_css('.bg-gray-100')
  end

  it 'affiche un badge validé' do
    render_inline(described_class.new(status: :posted))
    expect(page).to have_text('Posted')
    expect(page).to have_css('.bg-emerald-100')
  end

  it 'affiche un badge annulé' do
    render_inline(described_class.new(status: :reversed))
    expect(page).to have_text('Cancelled')
    expect(page).to have_css('.bg-red-100')
  end

  it 'accepte un statut sous forme de chaîne' do
    render_inline(described_class.new(status: 'posted'))
    expect(page).to have_text('Posted')
  end
end
