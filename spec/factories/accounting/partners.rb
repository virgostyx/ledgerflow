FactoryBot.define do
  factory :partner, class: 'Accounting::Partner' do
    entity       { ActsAsTenant.current_tenant || create(:entity) }
    sequence(:name) { |n| "Partenaire #{n}" }
    partner_type { :customer }
    country      { 'BE' }
    active       { true }

    trait :supplier do
      partner_type { :supplier }
    end

    trait :both do
      partner_type { :both }
    end

    trait :inactive do
      active { false }
    end

    trait :with_vat do
      vat_number { 'BE0123456789' }
    end

    trait :with_iban do
      iban { 'BE68539007547034' }
      bic  { 'GKCCBEBB' }
    end
  end
end
