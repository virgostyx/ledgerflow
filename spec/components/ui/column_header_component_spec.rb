require 'rails_helper'

RSpec.describe Ui::ColumnHeaderComponent, type: :component do
  def header(key, query: {}, align: :left)
    render_inline(described_class.new(model: Accounting::Invoice, key: key, label: key.to_s.humanize,
                                      resource: 'invoices', query: query, path: '/accounting/sales', align: align))
  end

  it 'renders the label and a filter toggle' do
    header(:partner)
    expect(page).to have_text('Partner')
    expect(page).to have_css('button[data-action="dropdown#toggle"]')
  end

  it 'links to sort asc and desc, keeping other params and dropping the page' do
    header(:partner, query: { 'q' => { 'q' => 'x' }, 'page' => '3' })
    href = page.find_link('Sort A → Z')[:href]
    expect(href).to start_with('/accounting/sales?')
    expect(Rack::Utils.parse_nested_query(href.split('?').last)).to eq('q' => { 'q' => 'x' }, 'sort' => 'partner', 'dir' => 'asc')
    expect(page).to have_link('Sort Z → A')
  end

  it 'marks the current sort direction' do
    header(:partner, query: { 'sort' => 'partner', 'dir' => 'desc' })
    expect(page).to have_css('[data-sorted="desc"]')
  end

  it 'highlights the button when the column is filtered' do
    header(:partner, query: { 'f' => { 'partner' => %w[Acme] } })
    expect(page).to have_css('button.text-primary-600')
    expect(page).to have_link('Clear filter')
  end

  it 'is not highlighted without a filter' do
    header(:partner)
    expect(page).not_to have_css('button.text-primary-600')
    expect(page).not_to have_link('Clear filter')
  end

  it 'lazy loads the value list for a string column' do
    header(:partner, query: { 'f' => { 'status' => %w[draft] } })
    frame = page.find('turbo-frame[loading="lazy"]', visible: :all)
    expect(frame[:src]).to include('/accounting/column_values/invoices/partner')
    expect(frame[:src]).to include('status')
  end

  it 'lists enum keys as checkboxes, checked when selected' do
    header(:status, query: { 'f' => { 'status' => %w[posted] } })
    expect(page).to have_field('f[status][]', type: 'checkbox', count: 5, visible: :all)
    expect(page).to have_checked_field('Posted', visible: :all)
    expect(page).to have_unchecked_field('Draft', visible: :all)
  end

  it 'offers Active/Inactive checkboxes for a boolean column' do
    render_inline(described_class.new(model: Accounting::Account, key: :active, label: 'Status', resource: 'accounts',
                                      query: { 'f' => { 'active' => %w[false] } }, path: '/accounting/settings/accounts'))
    expect(page).to have_checked_field('Inactive', visible: :all)
    expect(page).to have_unchecked_field('Active', visible: :all)
  end

  it 'renders from/to inputs for a date column and min/max for a decimal column' do
    header(:invoice_date, query: { 'f' => { 'invoice_date' => { 'from' => '2025-01-01' } } })
    expect(page).to have_field('f[invoice_date][from]', type: 'date', with: '2025-01-01', visible: :all)
    expect(page).to have_field('f[invoice_date][to]', type: 'date', visible: :all)
    header(:total_incl_vat)
    expect(page).to have_field('f[total_incl_vat][min]', type: 'number', visible: :all)
  end

  it 'keeps other filters as hidden fields but not its own' do
    header(:partner, query: { 'q' => { 'status' => 'draft' }, 'f' => { 'partner' => %w[A], 'status' => %w[paid] } })
    expect(page).to have_css('input[type=hidden][name="q[status]"][value="draft"]', visible: :all)
    expect(page).to have_css('input[type=hidden][name="f[status][]"][value="paid"]', visible: :all)
    expect(page).not_to have_css('input[type=hidden][name="f[partner][]"]', visible: :all)
  end

  it 'is sort-only for a column declared filter: false' do
    header(:invoice_number)
    expect(page).to have_link('Sort A → Z')
    expect(page).not_to have_css('form', visible: :all)
  end

  it 'anchors the menu to the right for right-aligned columns' do
    header(:total_incl_vat, align: :right)
    expect(page).to have_css('[data-dropdown-target="menu"].right-0', visible: :all)
  end
end
