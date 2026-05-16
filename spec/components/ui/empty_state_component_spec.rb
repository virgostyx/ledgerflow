require 'rails_helper'

RSpec.describe Ui::EmptyStateComponent, type: :component do
  it 'renders the title' do
    render_inline(described_class.new(title: 'No entries found'))
    expect(page).to have_text('No entries found')
  end

  it 'renders an optional description' do
    render_inline(described_class.new(title: 'No data', description: 'Create your first record to get started.'))
    expect(page).to have_text('Create your first record to get started.')
  end

  it 'omits description when not provided' do
    render_inline(described_class.new(title: 'No data'))
    expect(page).not_to have_css('p.text-gray-500')
  end

  it 'renders an icon' do
    render_inline(described_class.new(title: 'Empty', icon: :document))
    expect(page).to have_css('svg')
  end

  it 'uses dashed border container' do
    render_inline(described_class.new(title: 'Empty'))
    expect(page).to have_css('.border-dashed')
  end

  it 'renders action slot content' do
    render_inline(described_class.new(title: 'No data')) do |c|
      c.with_actions { '<a href="/new">Create new</a>'.html_safe }
    end
    expect(page).to have_text('Create new')
  end
end
