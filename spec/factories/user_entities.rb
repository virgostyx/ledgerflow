FactoryBot.define do
  factory :user_entity do
    association :user
    association :entity
    role   { :admin }
    active { true }

    trait :admin      do role { :admin }      end
    trait :accountant do role { :accountant } end
    trait :manager    do role { :manager }    end
    trait :auditor    do role { :auditor }    end
  end
end
