FactoryBot.define do
  factory :invoice_line, class: 'Accounting::InvoiceLine' do
    entity  { ActsAsTenant.current_tenant || create(:entity) }
    association :invoice, factory: :invoice
    association :account, factory: :account

    description { Faker::Commerce.product_name }
    quantity    { BigDecimal('1') }
    unit_price  { BigDecimal('100.00') }
    vat_rate    { BigDecimal('21.00') }
    position    { 1 }
  end
end
