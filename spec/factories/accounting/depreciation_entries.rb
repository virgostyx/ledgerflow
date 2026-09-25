FactoryBot.define do
  factory :depreciation_entry, class: 'Accounting::DepreciationEntry' do
    entity { ActsAsTenant.current_tenant || create(:entity) }
    association :fixed_asset, factory: [ :fixed_asset, :depreciable ]
    association :fiscal_year, factory: :fiscal_year
    journal_entry { association :journal_entry, fiscal_year: fiscal_year }
    amount { '600.00' }
  end
end
