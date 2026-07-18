require 'rails_helper'

RSpec.describe Accounting::StatusPresenter, type: :presenter do
  describe '#label' do
    it 'retourne Brouillon pour draft' do
      expect(described_class.new(:draft).label).to eq('Draft')
    end

    it 'retourne Validé pour posted' do
      expect(described_class.new(:posted).label).to eq('Posted')
    end

    it 'retourne Annulé pour reversed' do
      expect(described_class.new(:reversed).label).to eq('Cancelled')
    end

    it 'accepte une chaîne en plus d un symbole' do
      expect(described_class.new('draft').label).to eq('Draft')
    end

    it 'retourne Paid pour paid' do
      expect(described_class.new(:paid).label).to eq('Paid')
    end

    it 'retourne Cancelled pour cancelled' do
      expect(described_class.new(:cancelled).label).to eq('Cancelled')
    end

    it 'retourne Generated pour generated' do
      expect(described_class.new(:generated).label).to eq('Generated')
    end

    it 'retourne Executed pour executed' do
      expect(described_class.new(:executed).label).to eq('Executed')
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

    it 'retourne :success pour paid' do
      expect(described_class.new(:paid).badge_variant).to eq(:success)
    end

    it 'retourne :danger pour cancelled' do
      expect(described_class.new(:cancelled).badge_variant).to eq(:danger)
    end

    it 'retourne :warning pour generated' do
      expect(described_class.new(:generated).badge_variant).to eq(:warning)
    end

    it 'retourne :success pour executed' do
      expect(described_class.new(:executed).badge_variant).to eq(:success)
    end
  end
end
