require 'rails_helper'

RSpec.describe Accounting::DatePresenter, type: :presenter do
  describe '#format' do
    it 'formate une date style belge dd/mm/yyyy' do
      expect(described_class.new(Date.new(2026, 1, 15)).format).to eq('15/01/2026')
    end

    it 'retourne une chaîne vide pour nil' do
      expect(described_class.new(nil).format).to eq('')
    end
  end

  describe '#month_year' do
    it 'retourne mois/année formaté' do
      expect(described_class.new(Date.new(2026, 3, 15)).month_year).to eq('03/2026')
    end
  end

  describe '#vat_period' do
    it 'retourne T1 pour janvier' do
      expect(described_class.new(Date.new(2026, 1, 1)).vat_period).to eq('T1 2026')
    end

    it 'retourne T1 pour mars' do
      expect(described_class.new(Date.new(2026, 3, 31)).vat_period).to eq('T1 2026')
    end

    it 'retourne T2 pour avril' do
      expect(described_class.new(Date.new(2026, 4, 1)).vat_period).to eq('T2 2026')
    end

    it 'retourne T3 pour juillet' do
      expect(described_class.new(Date.new(2026, 7, 1)).vat_period).to eq('T3 2026')
    end

    it 'retourne T4 pour novembre' do
      expect(described_class.new(Date.new(2026, 11, 1)).vat_period).to eq('T4 2026')
    end
  end
end
