require 'rails_helper'

RSpec.describe Accounting::BalanceIndicatorComponent, type: :component do
  include_context 'with_open_fiscal_year'

  describe 'avec une écriture équilibrée' do
    let(:entry) { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year) }

    it 'affiche le montant total au débit' do
      render_inline(described_class.new(entry: entry))
      expect(page).to have_text('1 000,00 €')
    end

    it 'indique l équilibre avec une couleur verte' do
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css('.text-emerald-600')
    end
  end

  describe 'avec une écriture déséquilibrée' do
    let(:entry) { create(:journal_entry, :with_unbalanced_lines, fiscal_year: fiscal_year) }

    it 'indique le déséquilibre avec une couleur rouge' do
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css('.text-red-600')
    end
  end
end
