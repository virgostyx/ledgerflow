FactoryBot.define do
  factory :account, class: 'Accounting::Account' do
    sequence(:code) { |n| format('%06d', n) }
    label_fr        { Faker::Company.industry }
    account_class   { 6 }
    account_type    { :expense }
    normal_balance  { :debit }
    reconcilable    { false }
    active          { true }
    is_leaf         { true }
  end
end
