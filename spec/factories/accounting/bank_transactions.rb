FactoryBot.define do
  factory :bank_transaction, class: 'Accounting::BankTransaction' do
    entity  { ActsAsTenant.current_tenant || create(:entity) }
    association :bank_account, factory: :bank_account

    transaction_date { Date.current }
    amount           { BigDecimal('100.00') }
    currency         { 'EUR' }
    description      { 'Virement reçu' }
    sequence(:reference) { |n| "E2E-#{n.to_s.rjust(4, '0')}" }
    status           { :pending }
    raw_data         { {} }
  end
end
