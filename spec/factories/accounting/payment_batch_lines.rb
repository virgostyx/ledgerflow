FactoryBot.define do
  factory :payment_batch_line, class: 'Accounting::PaymentBatchLine' do
    entity  { ActsAsTenant.current_tenant || create(:entity) }
    association :payment_batch, factory: :payment_batch
    association :invoice, factory: %i[invoice supplier posted with_lines]

    amount                  { invoice.total_incl_vat }
    remittance_information  { "INV-#{invoice.invoice_number}" }
  end
end
