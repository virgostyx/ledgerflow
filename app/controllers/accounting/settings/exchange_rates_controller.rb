# Rates the accountant keys in (closing rates, spot rates): used to value foreign-currency balances.
class Accounting::Settings::ExchangeRatesController < Accounting::Settings::BaseController
  def index
    @rate  = Accounting::ExchangeRate.new(rate_date: Date.current)
    @rates = Accounting::ExchangeRate.order(rate_date: :desc, currency: :asc).limit(200)
  end

  def create
    rate = Accounting::ExchangeRate.new(rate_params)
    if rate.save
      redirect_to accounting_settings_exchange_rates_path, notice: "Rate saved."
    else
      redirect_to accounting_settings_exchange_rates_path, alert: rate.errors.full_messages.to_sentence
    end
  end

  def destroy
    Accounting::ExchangeRate.find(params[:id]).destroy!
    redirect_to accounting_settings_exchange_rates_path, notice: "Rate deleted."
  end

  private

  def rate_params
    p = params.require(:accounting_exchange_rate).permit(:currency, :rate_date, :rate)
    p[:rate] = p[:rate].to_s.strip.tr(",", ".")
    p
  end
end
