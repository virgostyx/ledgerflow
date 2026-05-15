require 'rails_helper'

RSpec.describe Accounting::MoneyPresenter, type: :presenter do
  describe '#format' do
    it 'formate un montant EUR style belge' do
      expect(described_class.new(1234.56).format).to eq('1 234,56 €')
    end

    it 'formate zéro' do
      expect(described_class.new(0).format).to eq('0,00 €')
    end

    it 'formate un montant négatif' do
      expect(described_class.new(-500).format).to eq('-500,00 €')
    end

    it 'arrondit à 2 décimales' do
      expect(described_class.new(BigDecimal('1.005')).format).to eq('1,01 €')
    end
  end

  describe '#format_signed' do
    it 'ajoute le signe + pour un montant positif' do
      expect(described_class.new(1000).format_signed).to eq('+1 000,00 €')
    end

    it 'montre le signe - pour un montant négatif' do
      expect(described_class.new(-500).format_signed).to eq('-500,00 €')
    end

    it 'affiche zéro sans signe' do
      expect(described_class.new(0).format_signed).to eq('0,00 €')
    end
  end

  describe '#css_class' do
    it 'retourne text-emerald-600 pour un montant positif' do
      expect(described_class.new(100).css_class).to eq('text-emerald-600')
    end

    it 'retourne text-red-600 pour un montant négatif' do
      expect(described_class.new(-100).css_class).to eq('text-red-600')
    end

    it 'retourne text-gray-500 pour zéro' do
      expect(described_class.new(0).css_class).to eq('text-gray-500')
    end
  end

  describe '#zero?' do
    it 'retourne true pour zéro' do
      expect(described_class.new(0)).to be_zero
    end

    it 'retourne false pour un montant non nul' do
      expect(described_class.new(1)).not_to be_zero
    end
  end
end
