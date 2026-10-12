FactoryBot.define do
  factory :partner_bank_account, class: "Accounting::PartnerBankAccount" do
    entity { ActsAsTenant.current_tenant || create(:entity) }
    association :partner, factory: %i[partner supplier]
    iban { "BE68539007547034" }
    holder_name { "Acme Ltd" }
    association :created_by, factory: :user
    first_seen_at { Time.current }
    cooling_until { 24.hours.from_now }

    trait :verified do
      status { :verified }
      association :verified_by, factory: :user
      verified_at { Time.current }
      verification_method { :phone_callback }
      cooling_until { 1.hour.ago }
    end
  end
end
