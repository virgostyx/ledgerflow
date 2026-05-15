class Accounting::MoneyPresenter
  include ActiveSupport::NumberHelper

  CURRENCY_SYMBOLS = { "EUR" => "€", "USD" => "$", "GBP" => "£" }.freeze

  def initialize(amount, currency: "EUR")
    @amount   = BigDecimal(amount.to_s)
    @currency = currency
  end

  def format
    number_to_currency(
      @amount,
      unit:      currency_symbol,
      separator: ",",
      delimiter: " ",
      format:    "%n %u",
      precision: 2
    )
  end

  def format_signed
    return format if @amount.zero?
    @amount.positive? ? "+#{format}" : format
  end

  def css_class
    return "text-gray-500"    if @amount.zero?
    return "text-emerald-600" if @amount.positive?
    "text-red-600"
  end

  def zero?
    @amount.zero?
  end

  private

  def currency_symbol
    CURRENCY_SYMBOLS.fetch(@currency, @currency)
  end
end
