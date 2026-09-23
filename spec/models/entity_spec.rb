require 'rails_helper'

RSpec.describe Entity, type: :model do
  subject { build(:entity) }

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:legal_name) }
    it { should validate_presence_of(:country) }
  end

  describe 'associations' do
    it { should belong_to(:created_by).class_name('User') }
    it { should have_many(:user_entities).dependent(:destroy) }
    it { should have_many(:users).through(:user_entities) }
  end

  describe 'scopes' do
    let!(:active_entity)   { create(:entity, active: true) }
    let!(:inactive_entity) { create(:entity, active: false) }

    it '.active retourne les entités actives' do
      expect(Entity.active).to include(active_entity)
      expect(Entity.active).not_to include(inactive_entity)
    end
  end

  describe 'defaults' do
    it 'est active par défaut' do
      expect(Entity.new.active).to be true
    end

    it 'a BE comme pays par défaut' do
      expect(Entity.new.country).to eq('BE')
    end

    it 'a une périodicité de dépôt TVA trimestrielle par défaut' do
      expect(Entity.new).to be_quarterly
    end

    it 'a un régime TVA normal par défaut' do
      expect(Entity.new).to be_normal
    end
  end

  describe 'vat_filing_frequency' do
    it { should define_enum_for(:vat_filing_frequency).with_values(monthly: 0, quarterly: 1) }
  end

  describe 'vat_regime' do
    it { should define_enum_for(:vat_regime).with_values(normal: 0, franchise: 1) }
  end

  describe 'vat_number uniqueness' do
    it 'accepte deux entités sans vat_number' do
      create(:entity, vat_number: nil)
      entity2 = build(:entity, vat_number: nil)
      expect(entity2).to be_valid
    end

    it 'rejette deux entités avec le même vat_number' do
      create(:entity, vat_number: 'BE0123456789')
      entity2 = build(:entity, vat_number: 'BE0123456789')
      expect(entity2).not_to be_valid
    end
  end
end
