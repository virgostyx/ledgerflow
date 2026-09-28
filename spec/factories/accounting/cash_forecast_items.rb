FactoryBot.define do
  factory :cash_forecast_item, class: "Accounting::CashForecastItem" do
    entity { ActsAsTenant.current_tenant || create(:entity) }
    label { "Rent" }
    direction { :outflow }
    amount { BigDecimal("1000.00") }
    recurrence { :monthly }
    first_date { Date.current }
  end
end
