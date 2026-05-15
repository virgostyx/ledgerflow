FactoryBot.define do
  factory :journal_entry_line, class: 'Accounting::JournalEntryLine' do
    association :journal_entry
    association :account

    debit      { BigDecimal('0') }
    credit     { BigDecimal('0') }
    label      { Faker::Lorem.sentence(word_count: 4) }
    currency   { 'EUR' }
    sort_order { 0 }

    trait :debit do
      debit  { BigDecimal('100.00') }
      credit { BigDecimal('0') }
    end

    trait :credit do
      debit  { BigDecimal('0') }
      credit { BigDecimal('100.00') }
    end
  end
end
