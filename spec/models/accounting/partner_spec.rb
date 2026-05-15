require 'rails_helper'

RSpec.describe Accounting::Partner, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:partner_type) }

    describe 'vat_number' do
      it 'accepte BE + 10 chiffres commençant par 0' do
        expect(build(:partner, vat_number: 'BE0123456789')).to be_valid
      end

      it 'accepte BE + 10 chiffres commençant par 1' do
        expect(build(:partner, vat_number: 'BE1234567890')).to be_valid
      end

      it 'accepte nil' do
        expect(build(:partner, vat_number: nil)).to be_valid
      end

      it 'rejette un préfixe non belge' do
        expect(build(:partner, vat_number: 'FR12345678901')).not_to be_valid
      end

      it 'rejette un format trop court' do
        expect(build(:partner, vat_number: 'BE012345')).not_to be_valid
      end

      it 'rejette un premier chiffre autre que 0 ou 1' do
        expect(build(:partner, vat_number: 'BE2123456789')).not_to be_valid
      end
    end

    describe 'iban' do
      it 'accepte un IBAN belge valide' do
        expect(build(:partner, iban: 'BE68539007547034')).to be_valid
      end

      it 'accepte nil' do
        expect(build(:partner, iban: nil)).to be_valid
      end

      it 'rejette un IBAN non belge' do
        expect(build(:partner, iban: 'FR7630006000011234567890189')).not_to be_valid
      end

      it 'rejette un IBAN trop court' do
        expect(build(:partner, iban: 'BE123')).not_to be_valid
      end
    end
  end

  describe 'enums' do
    it do
      is_expected.to define_enum_for(:partner_type)
        .with_values(customer: 0, supplier: 1, both: 2)
        .backed_by_column_of_type(:integer)
    end
  end

  describe 'associations' do
    it do
      is_expected.to have_many(:journal_entry_lines)
        .class_name('Accounting::JournalEntryLine')
        .with_foreign_key(:partner_id)
    end
  end

  describe 'scopes' do
    let!(:customer) { create(:partner, partner_type: :customer) }
    let!(:supplier) { create(:partner, partner_type: :supplier) }
    let!(:both)     { create(:partner, partner_type: :both) }
    let!(:inactive) { create(:partner, active: false) }

    describe '.active' do
      it 'retourne uniquement les partenaires actifs' do
        expect(described_class.active).to include(customer, supplier, both)
        expect(described_class.active).not_to include(inactive)
      end
    end

    describe '.customers' do
      it 'inclut les clients et les tiers mixtes, exclut les fournisseurs purs' do
        expect(described_class.customers).to include(customer, both)
        expect(described_class.customers).not_to include(supplier)
      end
    end

    describe '.suppliers' do
      it 'inclut les fournisseurs et les tiers mixtes, exclut les clients purs' do
        expect(described_class.suppliers).to include(supplier, both)
        expect(described_class.suppliers).not_to include(customer)
      end
    end
  end
end
