require 'rails_helper'

RSpec.describe Ui::TooltipComponent, type: :component do
  it 'renders the tooltip text' do
    render_inline(described_class.new(text: 'Helpful hint')) { 'Hover me' }
    expect(page).to have_text('Helpful hint')
    expect(page).to have_text('Hover me')
  end

  it 'has a relative wrapper' do
    render_inline(described_class.new(text: 'Hint')) { 'Trigger' }
    expect(page).to have_css('.relative')
  end

  it 'positions tooltip above by default' do
    render_inline(described_class.new(text: 'Top tip')) { 'Trigger' }
    expect(page).to have_css('.bottom-full')
  end

  it 'positions tooltip below with position: :bottom' do
    render_inline(described_class.new(text: 'Bottom tip', position: :bottom)) { 'Trigger' }
    expect(page).to have_css('.top-full')
  end

  it 'positions tooltip to the right with position: :right' do
    render_inline(described_class.new(text: 'Right tip', position: :right)) { 'Trigger' }
    expect(page).to have_css('.left-full')
  end

  it 'is hidden by default and visible on hover' do
    render_inline(described_class.new(text: 'Hint')) { 'Trigger' }
    expect(page).to have_css('.opacity-0')
    expect(page).to have_css('.group-hover\\:opacity-100')
  end
end
