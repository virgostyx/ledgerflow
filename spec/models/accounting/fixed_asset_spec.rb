require 'rails_helper'

RSpec.describe Accounting::FixedAsset, type: :model do
  include_context 'with entity'

  describe 'validations' do
    subject { build(:fixed_asset) }

    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:acquisition_date) }
    it { should validate_presence_of(:vat_amount_initial) }
    it { should validate_numericality_of(:vat_amount_initial).is_greater_than(0) }
    it { should validate_numericality_of(:prorata_at_acquisition).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
  end

  describe 'enums' do
    it { should define_enum_for(:asset_category).with_values(movable: 0, immovable: 1) }
  end

  describe '#review_period_years' do
    it 'vaut 5 ans pour un bien meuble' do
      expect(build(:fixed_asset, asset_category: :movable).review_period_years).to eq(5)
    end

    it 'vaut 15 ans pour un immeuble' do
      expect(build(:fixed_asset, asset_category: :immovable).review_period_years).to eq(15)
    end
  end

  describe '#annual_tranche' do
    it 'divise la TVA initiale par la période de révision' do
      asset = build(:fixed_asset, asset_category: :movable, vat_amount_initial: '1000.00')
      expect(asset.annual_tranche).to eq(BigDecimal('200.00'))
    end
  end

  describe '#under_review?' do
    let(:asset) { build(:fixed_asset, asset_category: :movable, acquisition_date: Date.new(2024, 6, 1)) }

    it "est vrai pour l année d acquisition" do
      expect(asset.under_review?(2024)).to be true
    end

    it "est vrai pour la dernière année de la période (4 ans plus tard pour un meuble)" do
      expect(asset.under_review?(2028)).to be true
    end

    it "est faux après la fin de la période de révision" do
      expect(asset.under_review?(2029)).to be false
    end

    it "est faux avant l année d acquisition" do
      expect(asset.under_review?(2023)).to be false
    end

    context 'bien cédé' do
      let(:asset) { build(:fixed_asset, asset_category: :movable, acquisition_date: Date.new(2024, 6, 1), disposed_on: Date.new(2026, 3, 1)) }

      it "est faux pour l année suivant la cession" do
        expect(asset.under_review?(2027)).to be false
      end

      it "est vrai pour l année de la cession elle-même" do
        expect(asset.under_review?(2026)).to be true
      end
    end
  end

  describe '#remaining_review_years' do
    let(:asset) { build(:fixed_asset, asset_category: :movable, acquisition_date: Date.new(2024, 6, 1)) }

    it "compte l année en cours et les années restantes jusqu à la fin de la période" do
      # 2024..2028 = 5 ans ; à partir de 2026 il reste 2026,2027,2028 = 3
      expect(asset.remaining_review_years(2026)).to eq(3)
    end
  end
end
