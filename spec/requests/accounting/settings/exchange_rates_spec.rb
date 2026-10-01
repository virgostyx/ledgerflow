require "rails_helper"

RSpec.describe "Accounting::Settings::ExchangeRates", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)    { create(:user, role: :manager) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager, user: manager, entity: entity) }

  before { sign_in accountant }

  it "lists, creates and deletes rates" do
    get accounting_settings_exchange_rates_path
    expect(response).to have_http_status(:ok)

    expect {
      post accounting_settings_exchange_rates_path,
           params: { accounting_exchange_rate: { currency: "usd", rate_date: "2026-09-30", rate: "0,9512" } }
    }.to change(Accounting::ExchangeRate, :count).by(1)
    rate = Accounting::ExchangeRate.last
    expect([ rate.currency, rate.rate ]).to eq([ "USD", BigDecimal("0.9512") ])

    get accounting_settings_exchange_rates_path
    expect(response.body).to include("USD", "0.9512")

    expect { delete accounting_settings_exchange_rate_path(rate) }.to change(Accounting::ExchangeRate, :count).by(-1)
  end

  it "shows the error when the rate is invalid" do
    expect {
      post accounting_settings_exchange_rates_path,
           params: { accounting_exchange_rate: { currency: "EUR", rate_date: "2026-09-30", rate: "1" } }
    }.not_to change(Accounting::ExchangeRate, :count)
    expect(flash[:alert]).to be_present
  end

  it "is refused to a manager" do
    sign_in manager
    get accounting_settings_exchange_rates_path
    expect(response).to redirect_to(accounting_root_path)
  end
end
