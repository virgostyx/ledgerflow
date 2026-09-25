FactoryBot.define do
  factory :peppol_event, class: 'Accounting::PeppolEvent' do
    entity { ActsAsTenant.current_tenant || create(:entity) }
    association :invoice, factory: [ :invoice, :posted ]
    kind { :sent }
    message { nil }
  end
end
