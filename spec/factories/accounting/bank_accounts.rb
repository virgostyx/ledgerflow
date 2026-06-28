FactoryBot.define do
  factory :bank_account, class: 'Accounting::BankAccount' do
    entity  { ActsAsTenant.current_tenant || create(:entity) }
    association :journal, factory: [ :journal, :bank ], strategy: :create

    sequence(:iban) do |n|
      account = "0001234#{n.to_s.rjust(5, '0')}"
      numeric = "#{account}111400"
      check = 98 - (numeric.to_i % 97)
      "BE#{check.to_s.rjust(2, '0')}#{account}"
    end
    bic      { 'BBVABEBB' }
    label_fr { 'Compte bancaire ING' }
    currency { 'EUR' }
    balance  { BigDecimal('0') }
    active   { true }
  end
end
