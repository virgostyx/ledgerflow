require 'rails_helper'

RSpec.describe Ui::ConfirmModalComponent, type: :component do
  before { render_inline(described_class.new) }

  it 'renders with confirm data controller' do
    expect(page).to have_css('[data-controller="confirm"]')
  end

  it 'has a dialog role' do
    expect(page).to have_css('[role="dialog"]')
  end

  it 'is hidden by default' do
    expect(page).to have_css('.hidden')
  end

  it 'renders a confirm button' do
    expect(page).to have_css('[data-confirm-target="confirmButton"]')
  end

  it 'renders a cancel button' do
    expect(page).to have_css('button', text: 'Cancel')
  end

  it 'has Esc key and Enter key handlers' do
    expect(page).to have_css('[data-action*="keydown.esc@window->confirm#cancel"]')
  end

  it 'closes on backdrop click' do
    expect(page).to have_css('[data-action*="click->confirm#cancel"]')
  end

  it 'renders the message target' do
    expect(page).to have_css('[data-confirm-target="message"]')
  end
end
