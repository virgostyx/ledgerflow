FactoryBot.define do
  factory :period_lock, class: "Accounting::PeriodLock" do
    entity    { ActsAsTenant.current_tenant || create(:entity) }
    kind      { :accounting }
    starts_on { Date.current.beginning_of_month }
    ends_on   { Date.current.end_of_month }
    status    { :locked }
    association :locked_by, factory: :user
    locked_at { Time.current }
  end
end
