require "rails_helper"

# F11: the entry form asks for the rate of a currency on a date (the entity's rules), to show it and the EUR equivalent as the person types.
RSpec.describe "Exchange rate lookup", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let(:day) { Date.new(2026, 9, 30) }

  before { sign_in accountant }

  def lookup(**params) = get(accounting_exchange_rate_lookup_path, params: params, as: :json)

  it "gives the rate of the date under the rules of the entity, and whether this person may type another" do
    Accounting::ExchangeRate.create!(currency: "USD", rate_date: day, rate: "1.12345678", rate_type: :daily, source: "ecb")
    lookup(currency: "USD", date: day.iso8601)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("rate" => "1.12345678", "can_override" => true)
  end

  it "says it cannot override for someone who may not" do
    Accounting::ExchangeRate.create!(currency: "USD", rate_date: day, rate: "1.1", rate_type: :daily, source: "ecb")
    sign_in assistant
    lookup(currency: "USD", date: day.iso8601)
    expect(response.parsed_body["can_override"]).to be(false)
  end

  it "is 1 for EUR" do
    lookup(currency: "EUR", date: day.iso8601)
    expect(response.parsed_body).to include("rate" => "1.0")
  end

  it "answers with the message that names the currency and the date when the rate is missing, never another rate" do
    Accounting::ExchangeRate.create!(currency: "USD", rate_date: day - 1, rate: "1.1", rate_type: :daily, source: "ecb")
    lookup(currency: "USD", date: day.iso8601)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["error"]).to include("USD", "30/09/2026")
    expect(response.parsed_body).not_to have_key("rate")
  end

  it "refuses a currency or a date that is not one" do
    lookup(currency: "US", date: day.iso8601)
    expect(response).to have_http_status(:unprocessable_content)
    lookup(currency: "USD", date: "nope")
    expect(response).to have_http_status(:unprocessable_content)
  end
end
