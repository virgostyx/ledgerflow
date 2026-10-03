FactoryBot.define do
  factory :user_entity do
    association :user
    association :entity
    role   { :admin }
    active { true }
    valid_until { Date.current + 365 if role.to_s == "auditor" } # an external auditor's access always ends (spec §4)

    trait :admin      do role { :admin }      end
    trait :accountant do role { :accountant } end
    trait :manager    do role { :manager }    end
    trait :auditor    do role { :auditor }    end
    trait :assistant  do role { :assistant }  end
  end
end
