require 'rails_helper'

RSpec.describe Ui::BackToTopComponent, type: :component do
  before { render_inline(described_class.new) }

  it 'has the back-to-top data controller' do
    expect(page).to have_css('[data-controller="back-to-top"]')
  end

  it 'has a scroll-to-top action' do
    expect(page).to have_css('[data-action*="back-to-top#scrollToTop"]')
  end

  it 'starts invisible' do
    expect(page).to have_css('.opacity-0')
  end

  it 'has pointer-events-none initially' do
    expect(page).to have_css('.pointer-events-none')
  end

  it 'is fixed bottom-right' do
    expect(page).to have_css('.fixed.bottom-6.right-6')
  end

  it 'has an accessible aria-label' do
    expect(page).to have_css('[aria-label="Back to top"]')
  end
end
