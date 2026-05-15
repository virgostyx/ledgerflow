require 'rails_helper'

RSpec.describe Layouts::ReconciliationPanelComponent, type: :component do
  let(:transactions) do
    [
      { date: Date.new(2026, 3, 1), label: 'Virement reçu',   amount: BigDecimal('1000.00'),  reconciled: false },
      { date: Date.new(2026, 3, 2), label: 'Paiement loyer',  amount: BigDecimal('-800.00'),  reconciled: true  }
    ]
  end

  before { render_inline(described_class.new(transactions: transactions, account_label: 'Compte BNP')) }

  it 'affiche le libellé du compte' do
    expect(page).to have_text('Compte BNP')
  end

  it 'affiche les libellés de transactions' do
    expect(page).to have_text('Virement reçu')
    expect(page).to have_text('Paiement loyer')
  end

  it 'affiche les montants' do
    expect(page).to have_text('1 000,00 €')
    expect(page).to have_text('800,00 €')
  end

  it 'distingue les transactions lettrées et non lettrées' do
    expect(page).to have_css('.reconciled')
    expect(page).to have_css('.unreconciled')
  end
end
