# F11: the rate of a currency on a date under the entity's rules, as JSON, for the forms that show it with the EUR equivalent. Reads only; nothing is
# fetched from the network and a missing rate is an error that says which, never another rate.
class Accounting::ExchangeRatesController < ApplicationController
  def lookup
    authorize Accounting::ExchangeRate, :index?
    currency = params[:currency].to_s.upcase
    date = Date.iso8601(params[:date].to_s)
    return render(json: { error: "Not a currency code" }, status: :unprocessable_content) unless currency.match?(/\A[A-Z]{3}\z/)

    rate = Fx::RateFor.call(currency, document_date: date, accounting_date: date)
    render json: { rate: rate.to_s("F"), can_override: Accounting::ExchangeRatePolicy.new(current_user, Accounting::ExchangeRate).create? }
  rescue Date::Error
    render json: { error: "Not a date" }, status: :unprocessable_content
  rescue Fx::MissingRate => e
    render json: { error: e.message, can_override: Accounting::ExchangeRatePolicy.new(current_user, Accounting::ExchangeRate).create? }, status: :not_found
  end
end
