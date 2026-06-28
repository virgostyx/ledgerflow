FactoryBot.define do
  factory :analytical_axis, class: "Accounting::AnalyticalAxis" do
    entity          { ActsAsTenant.current_tenant || create(:entity) }
    sequence(:code) { |n| "AX#{n}" }
    label_fr { Faker::Lorem.words(number: 2).join(" ").capitalize }
    label_nl { nil }
    active   { true }
    required_for_account_classes { [] }

    trait :proj do
      code     { "PROJ" }
      label_fr { "Projects" }
    end

    trait :act do
      code     { "ACT" }
      label_fr { "Activities" }
    end

    trait :fin do
      code     { "FIN" }
      label_fr { "Funding Sources" }
    end

    trait :budg do
      code     { "BUDG" }
      label_fr { "Budget Lines" }
    end
  end
end
