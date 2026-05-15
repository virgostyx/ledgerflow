FactoryBot.define do
  factory :journal, class: 'Accounting::Journal' do
    sequence(:code)     { |n| "J#{n.to_s.rjust(2, '0')}" }
    label_fr            { 'Journal divers' }
    journal_type        { :misc }
    sequence_prefix { 'JNL' }
    current_sequence    { 0 }
    active              { true }

    trait :purchase do
      code             { 'ACH' }
      label_fr         { 'Achats' }
      journal_type     { :purchase }
      sequence_prefix  { 'ACH' }
    end

    trait :sale do
      code             { 'VTE' }
      label_fr         { 'Ventes' }
      journal_type     { :sale }
      sequence_prefix  { 'VTE' }
    end

    trait :bank do
      code             { 'BNQ' }
      label_fr         { 'Banque' }
      journal_type     { :bank }
      sequence_prefix  { 'BNQ' }
    end
  end
end
