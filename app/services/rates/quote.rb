# A rate read from a source (F11): units of `currency` for 1 EUR on `date`, of a kind (Accounting::ExchangeRate.rate_types) and a source.
Rates::Quote = Struct.new(:currency, :date, :rate, :type, :source, keyword_init: true)
