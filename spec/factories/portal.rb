FactoryBot.define do
  factory :portal_user do
    sequence(:email) { |n| "client#{n}@client.example" }
    full_name { "Client Person" }
    status { "active" }
    password { "correct horse battery" }
    totp_secret { Totp.generate_secret }
    totp_enabled_at { Time.current }
    association :created_by, factory: :user
  end
end
