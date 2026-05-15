require 'rails_helper'

RSpec.describe Ui::SpinnerComponent, type: :component do
  it 'renders a spinner' do
    render_inline(described_class.new)
    expect(page).to have_css('.animate-spin')
  end

  it 'renders with sm size by default' do
    render_inline(described_class.new)
    expect(page).to have_css('.h-4.w-4')
  end

  it 'renders with lg size' do
    render_inline(described_class.new(size: :lg))
    expect(page).to have_css('.h-8.w-8')
  end

  it 'uses indigo color by default' do
    render_inline(described_class.new)
    expect(page).to have_css('.text-indigo-600')
  end
end
