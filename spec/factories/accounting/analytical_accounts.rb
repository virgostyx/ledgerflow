FactoryBot.define do
  factory :analytical_account, class: "Accounting::AnalyticalAccount" do
    association :analytical_axis

    sequence(:code)  { |n| "ACC#{n}" }
    label_fr         { Faker::Lorem.words(number: 3).join(" ").capitalize }
    label_nl         { nil }
    active           { true }
  end
end
