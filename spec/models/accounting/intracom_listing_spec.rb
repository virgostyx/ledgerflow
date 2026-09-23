require 'rails_helper'

RSpec.describe Accounting::IntracomListing, type: :model do
  include_context 'with_open_fiscal_year'

  describe 'associations' do
    it { should belong_to(:fiscal_year).class_name('Accounting::FiscalYear') }
    it { should have_many(:lines).class_name('Accounting::IntracomListingLine').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:intracom_listing, fiscal_year: fiscal_year) }

    it { should validate_presence_of(:period_start) }
    it { should validate_presence_of(:period_end) }

    it 'rejette si period_end < period_start' do
      listing = build(:intracom_listing, fiscal_year: fiscal_year,
                      period_start: Date.new(2025, 4, 1), period_end: Date.new(2025, 3, 31))
      expect(listing).not_to be_valid
      expect(listing.errors[:period_end]).to be_present
    end
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(draft: 0, submitted: 1) }
  end

  describe 'defaults' do
    it 'démarre en statut draft' do
      expect(build(:intracom_listing, fiscal_year: fiscal_year).status).to eq('draft')
    end
  end

  describe '#total_amount' do
    it 'additionne les montants de toutes les lignes' do
      listing = create(:intracom_listing, fiscal_year: fiscal_year)
      create(:intracom_listing_line, intracom_listing: listing, amount: '1000.00')
      create(:intracom_listing_line, intracom_listing: listing, amount: '500.00')
      expect(listing.total_amount).to eq(BigDecimal('1500.00'))
    end

    it 'retourne 0 sans ligne' do
      listing = create(:intracom_listing, fiscal_year: fiscal_year)
      expect(listing.total_amount).to eq(BigDecimal('0'))
    end
  end
end
