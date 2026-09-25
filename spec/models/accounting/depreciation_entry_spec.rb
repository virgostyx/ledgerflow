require 'rails_helper'

RSpec.describe Accounting::DepreciationEntry, type: :model do
  include_context 'with_open_fiscal_year'

  describe 'associations' do
    it { should belong_to(:fixed_asset).class_name('Accounting::FixedAsset') }
    it { should belong_to(:fiscal_year).class_name('Accounting::FiscalYear') }
    it { should belong_to(:journal_entry).class_name('Accounting::JournalEntry') }
  end

  describe 'validations' do
    subject { build(:depreciation_entry, fiscal_year: fiscal_year) }

    it { should validate_numericality_of(:amount).is_greater_than(0) }

    it 'refuse une seconde dotation pour la même immobilisation et le même exercice' do
      first = create(:depreciation_entry, fiscal_year: fiscal_year)
      duplicate = build(:depreciation_entry, fixed_asset: first.fixed_asset, fiscal_year: fiscal_year)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:fixed_asset_id]).to be_present
    end
  end

  describe 'Accounting::FixedAsset#depreciation_entries' do
    it 'liste les dotations comptabilisées de l immobilisation' do
      entry = create(:depreciation_entry, fiscal_year: fiscal_year)
      expect(entry.fixed_asset.depreciation_entries).to eq([ entry ])
    end

    it 'empêche de supprimer une immobilisation déjà amortie' do
      entry = create(:depreciation_entry, fiscal_year: fiscal_year)
      expect(entry.fixed_asset.destroy).to be false
      expect(entry.fixed_asset.errors[:base]).to be_present
    end
  end
end
