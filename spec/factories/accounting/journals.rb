FactoryBot.define do
  factory :journal, class: "Accounting::Journal" do
    sequence(:code)     { |n| "J#{n.to_s.rjust(2, '0')}" }
    label_fr            { "Journal divers" }
    journal_type        { :misc }
    sequence_prefix     { "JNL" }
    current_sequence    { 0 }
    active              { true }

    trait :purchase do
      code            { "ACH" }
      label_fr        { "Achats" }
      journal_type    { :purchase }
      sequence_prefix { "ACH" }
      association :default_account, factory: [ :account, :supplier ]
    end

    trait :sale do
      code            { "VTE" }
      label_fr        { "Ventes" }
      journal_type    { :sale }
      sequence_prefix { "VTE" }
      association :default_account, factory: [ :account, :customer ]
    end

    trait :bank do
      sequence(:code)            { |n| "BNQ#{n}" }
      label_fr                   { "Banque" }
      journal_type               { :bank }
      sequence(:sequence_prefix) { |n| "BNQ#{n}" }
      association :default_account, factory: [ :account, :bank ]
    end

    trait :cash do
      sequence(:code)            { |n| "CSH#{n}" }
      label_fr                   { "Caisse" }
      journal_type               { :cash }
      sequence(:sequence_prefix) { |n| "CSH#{n}" }
      association :default_account, factory: [ :account, :cash ]
    end
  end
end
