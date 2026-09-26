FactoryBot.define do
  factory :payment_reminder, class: 'Accounting::PaymentReminder' do
    entity  { ActsAsTenant.current_tenant || create(:entity) }
    association :partner, factory: :partner
    association :sent_by, factory: :user

    level     { 1 }
    recipient { 'client@example.com' }
    subject   { 'Payment reminder' }
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
