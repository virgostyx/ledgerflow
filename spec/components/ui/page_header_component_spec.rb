require 'rails_helper'

RSpec.describe Ui::PageHeaderComponent, type: :component do
  it 'renders the title' do
    render_inline(described_class.new(title: 'Journal Entries'))
    expect(page).to have_css('h1', text: 'Journal Entries')
  end

  it 'renders an optional description' do
    render_inline(described_class.new(title: 'Invoices', description: 'Manage your invoices.'))
    expect(page).to have_text('Manage your invoices.')
  end

  it 'omits description when not provided' do
    render_inline(described_class.new(title: 'Title'))
    expect(page).not_to have_css('p.text-gray-600')
  end

  it 'renders a back link when back_path is given' do
    render_inline(described_class.new(title: 'Detail', back_path: '/entries', back_text: 'Back to entries'))
    expect(page).to have_link('Back to entries', href: '/entries')
  end

  it 'omits back link when no back_path' do
    render_inline(described_class.new(title: 'Title'))
    expect(page).not_to have_link
  end

  it 'renders actions slot content' do
    render_inline(described_class.new(title: 'Title')) do |c|
      c.with_actions { '<a href="/new">New</a>'.html_safe }
    end
    expect(page).to have_text('New')
  end
end
