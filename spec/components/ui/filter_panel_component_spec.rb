require 'rails_helper'

RSpec.describe Ui::FilterPanelComponent, type: :component do
  it 'renders the Filters toggle button' do
    render_inline(described_class.new) { 'filter fields' }
    expect(page).to have_button('Filters')
  end

  it 'renders field slot content' do
    render_inline(described_class.new) do |c|
      c.with_fields { '<input type="text" name="q">'.html_safe }
    end
    expect(page).to have_css('input[name="q"]')
  end

  it 'is collapsed by default when no active filters' do
    render_inline(described_class.new) { 'fields' }
    expect(page).to have_css('[data-filter-panel-target="panel"].hidden')
  end

  it 'is open by default when active_count > 0' do
    render_inline(described_class.new(active_count: 2)) { 'fields' }
    expect(page).not_to have_css('[data-filter-panel-target="panel"].hidden')
  end

  it 'shows the active filter count badge' do
    render_inline(described_class.new(active_count: 3)) { 'fields' }
    expect(page).to have_text('3')
  end

  it 'has filter-panel data controller' do
    render_inline(described_class.new) { 'fields' }
    expect(page).to have_css('[data-controller="filter-panel"]')
  end
end
