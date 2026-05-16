require 'rails_helper'

RSpec.describe Accounting::InvoiceCardComponent, type: :component do
  include_context 'with_open_fiscal_year'

  let(:partner) { create(:partner, name: 'ACME SA') }
  let(:invoice) do
    create(:invoice,
           partner:       partner,
           fiscal_year:   fiscal_year,
           invoice_type:  :customer,
           invoice_date:  Date.new(2026, 3, 15),
           total_incl_vat: BigDecimal('1210.00'),
           invoice_number: 'VTE2026/0001',
           status:        :posted)
  end

  before { render_inline(described_class.new(invoice: invoice)) }

  it 'affiche le numéro de facture' do
    expect(page).to have_text('VTE2026/0001')
  end

  it 'affiche le nom du partenaire' do
    expect(page).to have_text('ACME SA')
  end

  it 'affiche le total formaté' do
    expect(page).to have_text('1 210,00 €')
  end

  it 'affiche la date formatée' do
    expect(page).to have_text('15/03/2026')
  end

  it 'affiche le badge de statut' do
    expect(page).to have_text('Posted')
  end
end
