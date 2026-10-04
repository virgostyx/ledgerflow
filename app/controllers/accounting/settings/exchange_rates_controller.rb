# Exchange rates (units of currency for 1 EUR) and the rules of the entity about them (F11): the rates by kind and source, typed by hand (with a reason, by
# those who may override rates), imported from the ECB, InforEuro or a CSV file, the rules (which rate, on which date, which accounts, how unrealized
# differences are treated), and the rates still missing for the currencies in use.
class Accounting::Settings::ExchangeRatesController < Accounting::Settings::BaseController
  RULE_FIELDS = %i[rate_policy rate_date_basis rate_alert_pct fx_realized_as_draft fx_loss_account_code fx_gain_account_code fx_unrealized_loss fx_unrealized_gain].freeze

  before_action :authorize_override!, except: %i[index rules]

  def index
    @rate  = Accounting::ExchangeRate.new(rate_date: Date.current, rate_type: :manual)
    scope  = Accounting::ExchangeRate.all
    scope  = scope.where(currency: params[:currency].to_s.upcase) if params[:currency].present?
    scope  = scope.where(rate_type: params[:rate_type]) if Accounting::ExchangeRate.rate_types.key?(params[:rate_type].to_s)
    @rates = scope.order(rate_date: :desc, currency: :asc, id: :desc).limit(200)
    @missing = Fx::MissingRates.call
    @entity = ActsAsTenant.current_tenant
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

  def import_ecb
    quotes = params[:history].present? ? Rates::Ecb.history : Rates::Ecb.daily
    report(Rates::Import.call(quotes: quotes, user: current_user), "ECB")
  rescue Rates::Error => e
    redirect_to accounting_settings_exchange_rates_path, alert: e.message
  end

  def import_inforeuro
    year, month = params[:month].to_s.split("-").map(&:to_i)
    return redirect_to(accounting_settings_exchange_rates_path, alert: "Choose a month.") unless year && month

    report(Rates::Import.call(quotes: Rates::InforEuro.month(year, month), user: current_user), "InforEuro")
  rescue Rates::Error => e
    redirect_to accounting_settings_exchange_rates_path, alert: e.message
  end

  def import_csv
    file = params[:file]
    return redirect_to(accounting_settings_exchange_rates_path, alert: "Choose a CSV file.") unless file.respond_to?(:read)

    fetched = Rates::Csv.parse(file.read.force_encoding("UTF-8"), filename: file.original_filename.to_s)
    report(Rates::Import.call(quotes: fetched.quotes, user: current_user), "CSV", errors: fetched.errors)
  rescue Rates::Error => e
    redirect_to accounting_settings_exchange_rates_path, alert: e.message
  end

  def rules
    entity = ActsAsTenant.current_tenant
    if entity.update(rules_params)
      redirect_to accounting_settings_exchange_rates_path, notice: "Rules saved."
    else
      redirect_to accounting_settings_exchange_rates_path, alert: entity.errors.full_messages.to_sentence
    end
  end

  private

  def authorize_override!
    return if Accounting::ExchangeRatePolicy.new(current_user, Accounting::ExchangeRate).create?

    redirect_to accounting_settings_exchange_rates_path, alert: t("errors.not_authorized")
  end

  # `errors` are the lines of a file that could not be read, as [line, why]; `result.rejected` the quotes that were not kept.
  def report(result, source, errors: [])
    flash[:notice] = "#{source}: #{helpers.pluralize(result.created + result.updated, 'rate')} stored, #{result.unchanged} already there."
    problems = errors.map { |line, why| "line #{line}: #{why}" } + result.rejected.map { |_, why| why }
    flash[:alert] = "Left out: #{problems.join('; ')}." if problems.any?
    redirect_to accounting_settings_exchange_rates_path
  end

  def rate_params
    p = params.require(:accounting_exchange_rate).permit(:currency, :rate_date, :rate, :reason, :rate_type)
    p[:rate] = p[:rate].to_s.strip.tr(",", ".")
    p[:rate_type] = "manual" unless Accounting::ExchangeRate.rate_types.key?(p[:rate_type].to_s)
    p.merge(source: "manual", created_by: current_user) # typed here, so from "manual", with its reason
  end

  def rules_params
    p = params.require(:entity).permit(*RULE_FIELDS, :rate_fallback_currencies)
    p[:rate_fallback_currencies] = p[:rate_fallback_currencies].to_s.split(/[\s,;]+/).map(&:upcase).compact_blank if p.key?(:rate_fallback_currencies)
    p
  end
end
