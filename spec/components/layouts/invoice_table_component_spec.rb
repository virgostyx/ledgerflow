require 'rails_helper'

RSpec.describe Layouts::InvoiceTableComponent, type: :component do
  include_context 'with_open_fiscal_year'

  let(:partner)  { create(:partner, name: 'ACME SA') }
  let(:invoices) do
    [
      create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year,
             invoice_number: 'VTE2026/0001', total_incl_vat: BigDecimal('1210.00'),
             invoice_date: Date.new(2026, 3, 1)),
      create(:invoice, :draft,  partner: partner, fiscal_year: fiscal_year,
             invoice_date: Date.new(2026, 3, 2))
    ]
  end

  before { render_inline(described_class.new(invoices: invoices)) }

  it 'affiche les numéros de facture' do
    expect(page).to have_text('VTE2026/0001')
  end

  it 'affiche le nom du partenaire' do
    expect(page).to have_text('ACME SA')
  end

  it 'affiche les totaux formatés' do
    expect(page).to have_text('1 210,00 €')
  end

  it 'affiche les statuts' do
    expect(page).to have_text('Validée')
    expect(page).to have_text('Brouillon')
  end

  it 'affiche un tableau' do
    expect(page).to have_css('table')
  end
end
