require 'rails_helper'

RSpec.describe Accounting::VatGrid do
  describe '.label' do
    it 'retourne le libellé anglais de la grille de vente à 21%' do
      expect(described_class.label(3)).to eq('Sales at 21%')
    end

    it 'retourne le libellé anglais de la TVA déductible' do
      expect(described_class.label(59)).to eq('Deductible VAT')
    end

    it 'retourne le code lui-même si aucun libellé connu' do
      expect(described_class.label(999)).to eq('999')
    end

    it 'accepte un code sous forme de chaîne' do
      expect(described_class.label('81')).to eq('Purchases of goods and materials')
    end
  end

  describe 'RATE_TO_GRID' do
    it 'mappe les taux de vente vers les grilles de base' do
      expect(described_class::RATE_TO_GRID[:sale]).to eq(21 => 3, 12 => 2, 6 => 1, 0 => 0)
    end
  end

  describe '.purchase_base_grid' do
    {
      '604000' => 81, '600000' => 81, '602000' => 81,
      '610000' => 82, '640400' => 82,
      '230000' => 83, '210000' => 83, '220100' => 83
    }.each do |code, grid|
      it "range le compte #{code} en grille #{grid}" do
        expect(described_class.purchase_base_grid(code)).to eq(grid)
      end
    end

    %w[620000 630100 651200 280000 290000 700000].each do |code|
      it "ne range pas le compte #{code}" do
        expect(described_class.purchase_base_grid(code)).to be_nil
      end
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

  describe 'TREATMENT_BASE_GRID' do
    it 'donne la grille de base pour une vente en régime intracom_goods' do
      expect(described_class::TREATMENT_BASE_GRID[:sale][:intracom_goods]).to eq(46)
    end

    it 'donne la grille de base pour un achat en régime intracom_services' do
      expect(described_class::TREATMENT_BASE_GRID[:purchase][:intracom_services]).to eq(88)
    end

    it 'donne la grille de base pour un achat en régime construction_reverse_charge' do
      expect(described_class::TREATMENT_BASE_GRID[:purchase][:construction_reverse_charge]).to eq(87)
    end

    it "n a pas de grille d achat pour un traitement qui n implique pas d autoliquidation" do
      expect(described_class::TREATMENT_BASE_GRID[:purchase][:export]).to be_nil
    end
  end

  describe 'SELF_ASSESSED_VAT_GRID' do
    it 'donne la grille de TVA due auto-liquidée pour intracom_goods' do
      expect(described_class::SELF_ASSESSED_VAT_GRID[:intracom_goods]).to eq(55)
    end

    it 'donne la grille de TVA due auto-liquidée pour construction_reverse_charge' do
      expect(described_class::SELF_ASSESSED_VAT_GRID[:construction_reverse_charge]).to eq(56)
    end
  end

  describe '.balance' do
    it 'renvoie la grille 71 quand la taxe due (XX) dépasse la TVA déductible (YY)' do
      grids = { '54' => 210, '55' => 21, '61' => 10, '63' => 5, '59' => 100, '62' => 20, '64' => 6 }
      expect(described_class.balance(grids)).to eq('71' => 120) # (210+21+10+5) - (100+20+6)
    end

    it 'renvoie la grille 72 quand YY dépasse XX' do
      expect(described_class.balance({ '54' => 50, '59' => 80 })).to eq('72' => 30)
    end

    it 'renvoie 71 à zéro quand XX = YY ou quand il n y a aucune opération' do
      expect(described_class.balance({ '54' => 50, '59' => 50 })).to eq('71' => 0)
      expect(described_class.balance({})).to eq('71' => 0)
    end
  end
end
