FactoryBot.define do
  factory :payment_batch, class: 'Accounting::PaymentBatch' do
    entity  { ActsAsTenant.current_tenant || create(:entity) }
    association :bank_account, factory: :bank_account

    status                    { :draft }
    requested_execution_date  { Date.current + 1 }
    total_amount              { BigDecimal('0') }

    trait :generated do
      status       { :generated }
      message_id   { SecureRandom.uuid }
      sepa_xml     { '<Document></Document>' }
      generated_at { Time.current }
    end

    trait :executed do
      status       { :executed }
      message_id   { SecureRandom.uuid }
      sepa_xml     { '<Document></Document>' }
      generated_at { Time.current }
      executed_at  { Time.current }
      association :journal_entry, factory: :journal_entry
    end

    trait :cancelled do
      status { :cancelled }
    end
  end
end
