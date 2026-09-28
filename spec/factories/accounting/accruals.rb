FactoryBot.define do
  factory :accrual, class: "Accounting::Accrual" do
    entity { ActsAsTenant.current_tenant || create(:entity) }
    association :fiscal_year
    accrual_type { :deferred_charge }
    description { "Annual insurance" }
    total_amount { BigDecimal("1200.00") }
    period_start { Date.new(2026, 10, 1) }
    period_end { Date.new(2027, 9, 30) }
    pl_account { Accounting::Account.find_by(code: "613000") || create(:account, code: "613000", label_fr: "Insurance", account_class: 6, account_type: :expense, normal_balance: :debit) }
    accrual_account { Accounting::Account.find_by(code: "490100") || create(:account, code: "490100", label_fr: "Deferred charges", account_class: 4, account_type: :asset, normal_balance: :debit) }
  end
end
