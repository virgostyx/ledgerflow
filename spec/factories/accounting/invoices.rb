FactoryBot.define do
  factory :invoice, class: 'Accounting::Invoice' do
    entity  { ActsAsTenant.current_tenant || create(:entity) }
    association :partner,     factory: :partner
    association :fiscal_year, factory: :fiscal_year, status: :open

    invoice_type  { :customer }
    invoice_date  { Date.current }
    due_date      { Date.current + 30 }
    status        { :draft }
    currency      { 'EUR' }

    trait :draft do
      status { :draft }
    end

    trait :posted do
      status { :posted }
      sequence(:invoice_number) { |n| "VTE#{Date.current.year}/#{n.to_s.rjust(4, '0')}" }
    end

    trait :paid do
      status { :paid }
      sequence(:invoice_number) { |n| "VTE#{Date.current.year}/#{n.to_s.rjust(4, '0')}" }
    end

    trait :cancelled do
      status { :cancelled }
    end

    trait :customer do
      invoice_type { :customer }
    end

    trait :supplier do
      invoice_type { :supplier }
    end

    trait :with_lines do
      after(:create) do |invoice|
        account = create(:account)
        create(:invoice_line, invoice: invoice, account: account,
               quantity: 1, unit_price: '1000.00', vat_rate: '21.00')
        invoice.compute_totals
        invoice.save!
      end
    end
  end
end
