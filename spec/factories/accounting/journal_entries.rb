FactoryBot.define do
  factory :journal_entry, class: 'Accounting::JournalEntry' do
    entity  { ActsAsTenant.current_tenant || create(:entity) }
    association :journal,     factory: :journal
    association :fiscal_year, factory: :fiscal_year

    entry_date  { Date.current }
    sequence(:reference) { |n| "ACH#{Date.current.year}/#{n.to_s.rjust(4, '0')}" }
    description { Faker::Lorem.sentence }
    status      { :draft }

    trait :draft do
      status { :draft }
    end

    trait :posted do
      status { :posted }
    end

    trait :reversed do
      status { :reversed }
    end

    trait :with_balanced_lines do
      after(:create) do |entry|
        debit_account  = create(:account, account_type: :expense,   normal_balance: :debit)
        credit_account = create(:account, account_type: :liability, normal_balance: :credit)
        # Defer the double-entry constraint so both lines can be inserted separately.
        # DatabaseCleaner never commits, so the deferred check never fires in tests.
        ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
        create(:journal_entry_line, journal_entry: entry, account: debit_account,
               debit: BigDecimal('1000.00'), credit: BigDecimal('0'))
        create(:journal_entry_line, journal_entry: entry, account: credit_account,
               debit: BigDecimal('0'), credit: BigDecimal('1000.00'))
      end
    end

    trait :with_unbalanced_lines do
      after(:create) do |entry|
        # Defer so the single debit line can be inserted (intentionally unbalanced for testing).
        ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
        create(:journal_entry_line, journal_entry: entry, account: create(:account),
               debit: BigDecimal('1000.00'), credit: BigDecimal('0'))
      end
    end
  end
end
