require 'rails_helper'

RSpec.describe Ui::SelectComponent, type: :component do
  let(:options) { [ [ 'Achats', 'ACH' ], [ 'Ventes', 'VTE' ], [ 'Banque', 'BNQ' ] ] }

  it 'renders a select with a label' do
    render_inline(described_class.new(name: 'journal', label: 'Journal', options: options))
    expect(page).to have_css('label', text: 'Journal')
    expect(page).to have_css('select[name="journal"]')
  end

  it 'renders all options' do
    render_inline(described_class.new(name: 'journal', label: 'Journal', options: options))
    expect(page).to have_css('option', text: 'Achats')
    expect(page).to have_css('option', text: 'Ventes')
    expect(page).to have_css('option', text: 'Banque')
  end

  it 'marks the selected option' do
    render_inline(described_class.new(name: 'journal', label: 'Journal',
                                      options: options, selected: 'VTE'))
    expect(page).to have_css('option[selected]', text: 'Ventes')
  end

  it 'renders an error state' do
    render_inline(described_class.new(name: 'journal', label: 'Journal',
                                      options: options, error: 'Requis'))
    expect(page).to have_css('.text-red-600', text: 'Requis')
  end

  it 'includes a blank option when prompt is given' do
    render_inline(described_class.new(name: 'journal', label: 'Journal',
                                      options: options, prompt: '— Choisir —'))
    expect(page).to have_css('option', text: '— Choisir —')
  end
end
