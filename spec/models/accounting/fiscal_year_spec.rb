require 'rails_helper'

RSpec.describe Accounting::FiscalYear, type: :model do
  include_context 'with entity'

  describe 'validations' do
    subject { build(:fiscal_year) }

    it { should validate_presence_of(:year) }
    it { should validate_presence_of(:start_date) }
    it { should validate_presence_of(:end_date) }
    it 'rejects a duplicate year within the same entity' do
      create(:fiscal_year, year: 2020, start_date: Date.new(2020, 1, 1), end_date: Date.new(2020, 12, 31), status: :closed)
      dup = build(:fiscal_year, year: 2020, start_date: Date.new(2020, 1, 1), end_date: Date.new(2020, 12, 31), status: :closed)
      expect(dup).not_to be_valid
    end

    it 'allows the same year in a different entity' do
      create(:fiscal_year, year: 2020, start_date: Date.new(2020, 1, 1), end_date: Date.new(2020, 12, 31), status: :closed)
      ActsAsTenant.with_tenant(create(:entity)) do
        expect(build(:fiscal_year, year: 2020, start_date: Date.new(2020, 1, 1), end_date: Date.new(2020, 12, 31), status: :closed)).to be_valid
      end
    end

    it 'est invalide si start_date >= end_date' do
      fy = build(:fiscal_year, start_date: Date.new(2025, 12, 31),
                               end_date:   Date.new(2025, 1, 1))
      expect(fy).not_to be_valid
      expect(fy.errors[:end_date]).to be_present
    end
  end

  describe 'enums' do
    it { should define_enum_for(:status)
           .with_values(open: 0, pre_closing: 1, closed: 2) }
  end

  describe 'scopes' do
    let!(:open_fy)   { create(:fiscal_year, year: 2024, status: :open) }
    let!(:closed_fy) { create(:fiscal_year, year: 2023,
                              start_date: Date.new(2023, 1, 1),
                              end_date:   Date.new(2023, 12, 31),
                              status: :closed) }

    it '.open retourne les exercices ouverts' do
      expect(Accounting::FiscalYear.open_years).to include(open_fy)
      expect(Accounting::FiscalYear.open_years).not_to include(closed_fy)
    end

    it '.current retourne l exercice actif' do
      expect(Accounting::FiscalYear.current).to eq(open_fy)
    end
  end

  describe '#open? #closed?' do
    it 'retourne true pour un exercice ouvert' do
      fy = build(:fiscal_year, status: :open)
      expect(fy.open?).to be true
      expect(fy.closed?).to be false
    end
  end

  describe 'un seul exercice open à la fois' do
    it 'est invalide si un autre exercice est déjà open' do
      create(:fiscal_year, year: 2024, status: :open)
      duplicate = build(:fiscal_year, year: 2025,
                        start_date: Date.new(2025, 1, 1),
                        end_date:   Date.new(2025, 12, 31),
                        status: :open)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:status]).to be_present
    end
  end
end
