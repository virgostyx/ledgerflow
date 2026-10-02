FactoryBot.define do
  factory :entity do
    sequence(:name)       { |n| "Entity #{n}" }
    sequence(:legal_name) { |n| "Entity #{n} ASBL" }
    legal_form  { "ASBL" }
    country     { "BE" }
    active      { true }
    features    { Entity::FEATURES.index_with { true } } # specs exercise the features; the column default is everything off
    vat_number  { nil }
    association :created_by, factory: :user
  end
end
