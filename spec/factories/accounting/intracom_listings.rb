FactoryBot.define do
  factory :intracom_listing, class: 'Accounting::IntracomListing' do
    entity  { ActsAsTenant.current_tenant || create(:entity) }
    association :fiscal_year, factory: :fiscal_year

    period_start { Date.new(2025, 1, 1) }
    period_end   { Date.new(2025, 3, 31) }
    status       { :draft }
  end

  factory :intracom_listing_line, class: 'Accounting::IntracomListingLine' do
    entity { ActsAsTenant.current_tenant || create(:entity) }
    association :intracom_listing
    association :partner
    code   { 'L' }
    amount { '1000.00' }
  end
end
