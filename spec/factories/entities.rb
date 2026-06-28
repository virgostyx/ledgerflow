FactoryBot.define do
  factory :entity do
    sequence(:name)       { |n| "Entity #{n}" }
    sequence(:legal_name) { |n| "Entity #{n} ASBL" }
    legal_form  { "ASBL" }
    country     { "BE" }
    active      { true }
    vat_number  { nil }
    association :created_by, factory: :user
  end
end
