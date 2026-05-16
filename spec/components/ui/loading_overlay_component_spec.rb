require 'rails_helper'

RSpec.describe Ui::LoadingOverlayComponent, type: :component do
  before { render_inline(described_class.new) }

  it 'has the loading-overlay data controller' do
    expect(page).to have_css('[data-controller="loading-overlay"]')
  end

  it 'is marked data-turbo-permanent' do
    expect(page).to have_css('[data-turbo-permanent]')
  end

  it 'starts hidden via opacity-0' do
    expect(page).to have_css('.opacity-0')
  end

  it 'is fixed and full-screen' do
    expect(page).to have_css('.fixed.inset-0')
  end

  it 'has a spinner element' do
    expect(page).to have_css('.lf-spinner')
  end

  it 'has a high z-index' do
    overlay = page.find('[data-controller="loading-overlay"]')
    expect(overlay[:class]).to include('z-')
  end
end
