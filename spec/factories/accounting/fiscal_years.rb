FactoryBot.define do
  factory :fiscal_year, class: 'Accounting::FiscalYear' do
    entity     { ActsAsTenant.current_tenant || create(:entity) }
    year       { Date.current.year }
    start_date { Date.current.beginning_of_year }
    end_date   { Date.current.end_of_year }
    status     { :open }

    trait :open do
      status { :open }
    end

    trait :pre_closing do
      status { :pre_closing }
    end

    trait :closed do
      status  { :closed }
      closed_at { Time.current }
    end
  end
end
