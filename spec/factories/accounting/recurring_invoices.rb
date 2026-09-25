FactoryBot.define do
  factory :recurring_invoice, class: 'Accounting::RecurringInvoice' do
    entity { ActsAsTenant.current_tenant || create(:entity) }
    source_invoice { create(:invoice, :posted) }
    frequency { :monthly }
    start_on  { Date.new(2026, 1, 31) }
  end
end
