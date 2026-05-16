require 'rails_helper'

RSpec.describe Ui::BreadcrumbsComponent, type: :component do
  let(:items) do
    [
      { label: 'Dashboard', path: '/accounting' },
      { label: 'Invoices', path: '/accounting/invoices' },
      { label: 'INV-001' }
    ]
  end

  before { render_inline(described_class.new(items: items)) }

  it 'renders each breadcrumb label' do
    expect(page).to have_text('Dashboard')
    expect(page).to have_text('Invoices')
    expect(page).to have_text('INV-001')
  end

  it 'renders links for items with a path' do
    expect(page).to have_link('Dashboard', href: '/accounting')
    expect(page).to have_link('Invoices', href: '/accounting/invoices')
  end

  it 'renders the last item as plain text (no link)' do
    expect(page).not_to have_link('INV-001')
    expect(page).to have_css('span', text: 'INV-001')
  end

  it 'renders chevron separators between items' do
    expect(page).to have_css('svg', minimum: 2)
  end

  it 'renders nothing when items are empty' do
    render_inline(described_class.new(items: []))
    expect(page).to have_no_css('nav')
  end
end
