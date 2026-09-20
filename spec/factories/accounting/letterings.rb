FactoryBot.define do
  factory :lettering, class: 'Accounting::Lettering' do
    entity  { ActsAsTenant.current_tenant || create(:entity) }
    association :account
    sequence(:code) { |n| "A#{('A'.ord + n % 26).chr}" }
    lettered_on { Date.current }
  end
end
