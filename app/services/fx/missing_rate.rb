# No exchange rate for a currency on a date (F11): the operation is refused, and the message names the currency, the date and where to enter the rate.
class Fx::MissingRate < StandardError
  attr_reader :currency, :date

  def initialize(currency, date, kind: nil)
    @currency = currency
    @date = date
    kind = " #{kind}" if kind
    super("No#{kind} exchange rate for #{currency} on #{Accounting::DatePresenter.new(date).format}: enter it in Settings > Exchange rates, then try again.")
  end
end
