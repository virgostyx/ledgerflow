class Accounting::CashForecastItemsController < ApplicationController
  def create
    authorize :report, :cash_forecast?, policy_class: Accounting::ReportPolicy

    item = Accounting::CashForecastItem.new(item_params)
    if item.save
      redirect_to accounting_reports_cash_forecast_path, notice: "Forecast item added."
    else
      redirect_to accounting_reports_cash_forecast_path, alert: item.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize :report, :cash_forecast?, policy_class: Accounting::ReportPolicy

    Accounting::CashForecastItem.find(params[:id]).destroy!
    redirect_to accounting_reports_cash_forecast_path, notice: "Forecast item removed."
  end

  private

  def item_params
    params.require(:accounting_cash_forecast_item).permit(:label, :direction, :amount, :recurrence, :first_date, :end_date)
  end
end
