# Foreign currency to euros, with the one convention of the application (F11): a rate is the number of units of foreign currency for 1 EUR
# (the ECB's), so EUR = foreign / rate. Rounded half up to the cent, on the exact quotient.
module Fx::Convert
  def self.to_eur(amount, rate)
    rate = BigDecimal(rate.to_s)
    raise ArgumentError, "The exchange rate must be positive (got #{rate.to_s('F')})" unless rate.positive?

    amount.to_d.div(rate, 20).round(2, half: :up)
  end
end
