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

  describe '.mapping (domestic sale rates)' do
    it 'mappe les taux de vente vers les grilles de base' do
      grids = { 21 => 3, 12 => 2, 6 => 1, 0 => 0 }
      expect(grids.keys.to_h { |rate| [ rate, described_class.mapping(:sale, :domestic, :invoice, rate: rate).base_grid ] }).to eq(grids)
    end

    it 'ne connaît pas un taux inconnu' do
      expect(described_class.mapping(:sale, :domestic, :invoice, rate: 5)).to be_nil
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

  describe 'grilles de TVA' do
    it 'donne la grille de la TVA due sur ventes, et celle de sa note de crédit' do
      expect(described_class.sale_due_vat_grid).to eq(54)
      expect(described_class.sale_due_vat_grid(:credit_note)).to eq(64)
    end

    it 'donne la grille de la TVA déductible sur achats, et celle de sa note de crédit' do
      expect(described_class.purchase_deductible_vat_grid).to eq(59)
      expect(described_class.purchase_deductible_vat_grid(:credit_note)).to eq(63)
    end

    it 'donne la grille de base d une vente selon le régime' do
      expect(described_class.mapping(:sale, :intracom_goods).base_grid).to eq(46)
      expect(described_class.sale_credit_grid(:intracom_services)).to eq(48)
      expect(described_class.sale_credit_grid(:export)).to eq(49)
    end

    it 'donne la grille de base d un achat en autoliquidation, identique pour la note de crédit' do
      expect(described_class.mapping(:purchase, :intracom_services).base_grid).to eq(88)
      expect(described_class.mapping(:purchase, :construction_reverse_charge, :credit_note).base_grid).to eq(87)
    end

    it 'n a pas de mapping d achat pour un traitement sans autoliquidation' do
      expect(described_class.mapping(:purchase, :export)).to be_nil
    end

    it 'donne la TVA due auto-liquidée et sa régularisation en note de crédit' do
      expect(described_class.mapping(:purchase, :intracom_goods).due_vat_grid).to eq(55)
      expect(described_class.mapping(:purchase, :construction_reverse_charge).due_vat_grid).to eq(56)
      expect(described_class.mapping(:purchase, :intracom_goods, :credit_note))
        .to have_attributes(due_vat_grid: 62, deductible_vat_grid: 61)
    end

    it 'regroupe les grilles récapitulatives des notes de crédit reçues' do
      expect(described_class.credit_note_recap_grids).to eq(84 => [ 86, 88 ], 85 => [ 81, 82, 83, 87 ])
      expect(described_class.reverse_charge_purchase_grids).to contain_exactly(86, 87, 88)
    end
  end

  describe 'pilotée par les données' do
    it 'reflète une modification du mapping après reset du cache' do
      mapping = described_class.mapping(:sale, :export)
      mapping.update!(base_grid: 99)
      described_class.reset! # after_commit does this in production; the transactional test never commits
      expect(described_class.mapping(:sale, :export).base_grid).to eq(99)
    ensure
      mapping.update!(base_grid: 47)
      described_class.reset!
    end
  end

  describe 'sans données' do
    it 'échoue bruyamment plutôt que de ne poster aucune grille' do
      described_class.reset!
      Accounting::VatGridMapping.delete_all
      expect { described_class.mapping(:sale, :export) }.to raise_error(described_class::NotSeeded)
    ensure
      Seeders::VatCodesSeeder.call
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
