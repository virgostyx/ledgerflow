class Accounting::MoneyPresenter
  include ActiveSupport::NumberHelper

  CURRENCY_SYMBOLS = { "EUR" => "€", "USD" => "$", "GBP" => "£" }.freeze

  # ISO 4217 active circulating currency codes (excludes precious metals, bonds/funds and test codes).
  SUPPORTED_CURRENCIES = %w[
    AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND BOB BRL BSD BTN BWP
    BYN BZD CAD CDF CHF CLP CNY COP CRC CUC CUP CVE CZK DJF DKK DOP DZD EGP ERN ETB EUR FJD FKP
    GBP GEL GHS GIP GMD GNF GTQ GYD HKD HNL HTG HUF IDR ILS INR IQD IRR ISK JMD JOD JPY KES KGS
    KHR KMF KPW KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK MNT MOP MRU MUR MVR
    MWK MXN MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG QAR RON RSD RUB RWF
    SAR SBD SCR SDG SEK SGD SHP SLE SOS SRD SSP STN SVC SYP SZL THB TJS TMT TND TOP TRY TTD TWD
    TZS UAH UGX USD UYU UZS VES VND VUV WST XAF XCD XOF XPF YER ZAR ZMW ZWG
  ].freeze

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
