require 'rails_helper'

RSpec.describe Accounting::StatusPresenter, type: :presenter do
  describe '#label' do
    it 'retourne Brouillon pour draft' do
      expect(described_class.new(:draft).label).to eq('Brouillon')
    end

    it 'retourne Validé pour posted' do
      expect(described_class.new(:posted).label).to eq('Validé')
    end

    it 'retourne Annulé pour reversed' do
      expect(described_class.new(:reversed).label).to eq('Annulé')
    end

    it 'accepte une chaîne en plus d un symbole' do
      expect(described_class.new('draft').label).to eq('Brouillon')
    end
  end

  describe '#badge_variant' do
    it 'retourne :default pour draft' do
      expect(described_class.new(:draft).badge_variant).to eq(:default)
    end

    it 'retourne :success pour posted' do
      expect(described_class.new(:posted).badge_variant).to eq(:success)
    end

    it 'retourne :danger pour reversed' do
      expect(described_class.new(:reversed).badge_variant).to eq(:danger)
    end
  end
end
