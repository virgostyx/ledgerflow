FactoryBot.define do
  factory :account, class: "Accounting::Account" do
    sequence(:code) { |n| format("%06d", n) }
    label_fr        { Faker::Company.industry }
    account_class   { 6 }
    account_type    { :expense }
    normal_balance  { :debit }
    reconcilable    { false }
    active          { true }
    is_leaf         { true }

    trait :bank do
      sequence(:code) { |n| "55#{n.to_s.rjust(4, '0')}" }
      account_class { 5 }
      account_type  { :asset }
      normal_balance { :debit }
      label_fr { "Compte bancaire" }
    end

    trait :cash do
      sequence(:code) { |n| "57#{n.to_s.rjust(4, '0')}" }
      account_class { 5 }
      account_type  { :asset }
      normal_balance { :debit }
      label_fr { "Caisse" }
    end

    trait :supplier do
      sequence(:code) { |n| "44#{n.to_s.rjust(4, '0')}" }
      account_class { 4 }
      account_type  { :liability }
      normal_balance { :credit }
      label_fr { "Fournisseurs" }
    end

    trait :customer do
      sequence(:code) { |n| "40#{n.to_s.rjust(4, '0')}" }
      account_class { 4 }
      account_type  { :asset }
      normal_balance { :debit }
      label_fr { "Clients" }
    end
  end
end
