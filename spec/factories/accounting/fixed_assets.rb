FactoryBot.define do
  factory :fixed_asset, class: 'Accounting::FixedAsset' do
    entity { ActsAsTenant.current_tenant || create(:entity) }
    description             { 'Office equipment' }
    acquisition_date        { Date.current }
    vat_amount_initial      { '1000.00' }
    prorata_at_acquisition  { '100.00' }
    asset_category          { :movable }

    # 12 000 EUR office IT equipment, 5 years, put in service in October 2026: 3 months in the first year.
    trait :depreciable do
      acquisition_date  { Date.new(2026, 10, 1) }
      in_service_date   { Date.new(2026, 10, 15) }
      acquisition_value { '12000.00' }
      useful_life_years { 5 }
      residual_value    { '0.00' }
      asset_account do
        Accounting::Account.find_by(code: '240200') ||
          create(:account, code: '240200', label_fr: 'Matériel informatique', account_class: 2,
                           account_type: :asset, normal_balance: :debit, entity: entity)
      end
    end
  end
end
