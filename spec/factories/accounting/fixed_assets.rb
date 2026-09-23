FactoryBot.define do
  factory :fixed_asset, class: 'Accounting::FixedAsset' do
    entity { ActsAsTenant.current_tenant || create(:entity) }
    description             { 'Office equipment' }
    acquisition_date        { Date.current }
    vat_amount_initial      { '1000.00' }
    prorata_at_acquisition  { '100.00' }
    asset_category          { :movable }
  end
end
