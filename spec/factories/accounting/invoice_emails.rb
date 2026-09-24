FactoryBot.define do
  factory :invoice_email, class: 'Accounting::InvoiceEmail' do
    entity  { ActsAsTenant.current_tenant || create(:entity) }
    association :invoice, factory: :invoice
    association :sent_by, factory: :user

    recipient { 'client@example.com' }
    subject   { 'Invoice VTE2026/0001' }
    status    { :queued }

    trait :sent do
      status  { :sent }
      sent_at { Time.current }
    end

    trait :failed do
      status { :failed }
      error  { 'Connection refused' }
    end
  end
end
