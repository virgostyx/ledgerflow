FactoryBot.define do
  factory :user do
    full_name { "#{Faker::Name.first_name} #{Faker::Name.last_name}" }
    email     { Faker::Internet.unique.email }
    password  { 'Password123!' }
    role      { :auditor }
    active    { true }
    locale    { 'fr' }

    trait :admin      do role { :admin }      end
    trait :accountant do role { :accountant } end
    trait :manager    do role { :manager }    end
    trait :auditor    do role { :auditor }    end
    trait :budget_user do role { :budget_user } end
  end
end
