require 'rails_helper'

RSpec.describe Accounting::VatGrid do
  describe '.label' do
    it 'retourne le libellé anglais de la grille de vente à 21%' do
      expect(described_class.label(1)).to eq('Sales at 21%')
    end

    it 'retourne le libellé anglais de la TVA déductible' do
      expect(described_class.label(59)).to eq('Deductible VAT')
    end

    it 'retourne le code lui-même si aucun libellé connu' do
      expect(described_class.label(999)).to eq('999')
    end

    it 'accepte un code sous forme de chaîne' do
      expect(described_class.label('81')).to eq('Purchases at 21%')
    end
  end

  describe 'RATE_TO_GRID' do
    it 'mappe les taux de vente vers les grilles de base' do
      expect(described_class::RATE_TO_GRID[:sale]).to eq(21 => 1, 12 => 2, 6 => 3, 0 => 0)
    end

    it 'mappe les taux d achat vers les grilles de base' do
      expect(described_class::RATE_TO_GRID[:purchase]).to eq(21 => 81, 12 => 82, 6 => 83)
    end
  end

  describe 'VAT_LINE_GRID' do
    it 'donne la grille de la ligne de TVA due sur ventes' do
      expect(described_class::VAT_LINE_GRID[:sale]).to eq(54)
    end

    it 'donne la grille de la ligne de TVA déductible sur achats' do
      expect(described_class::VAT_LINE_GRID[:purchase]).to eq(59)
    end
  end
end
