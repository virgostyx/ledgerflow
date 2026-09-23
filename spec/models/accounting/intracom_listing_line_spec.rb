require 'rails_helper'

RSpec.describe Accounting::IntracomListingLine, type: :model do
  include_context 'with_open_fiscal_year'

  let(:listing) { create(:intracom_listing, fiscal_year: fiscal_year) }

  describe 'associations' do
    it { should belong_to(:intracom_listing).class_name('Accounting::IntracomListing') }
    it { should belong_to(:partner).class_name('Accounting::Partner') }
  end

  describe 'validations' do
    subject { build(:intracom_listing_line, intracom_listing: listing) }

    it { should validate_presence_of(:amount) }
    it { should validate_inclusion_of(:code).in_array(%w[L S]) }
  end
end
