require "csv"

# Rates from a file the accountant brings (F11): columns currency, date (ISO) and rate (point or comma), and optionally type (daily, monthly_average,
# closing or manual). Each line is read on its own: the good ones are kept, each bad one is named by its line number with why (a zero or negative
# rate, a rate or a date that is not one, EUR, an unknown type).
class Rates::Csv
  REQUIRED = %w[currency date rate].freeze

  def self.parse(content, filename:)
    table = CSV.parse(content.to_s.delete_prefix("﻿"), headers: true, header_converters: ->(h) { h.to_s.strip.downcase })
    raise Rates::Error, "The file needs the columns currency, date, rate" unless (REQUIRED - table.headers.map(&:to_s)).empty?

    quotes = []
    errors = []
    table.each_with_index do |row, index|
      line = index + 2
      quote, problem = read(row, filename)
      problem ? errors << [ line, problem ] : quotes << quote
    end
    Rates::Fetched.new(quotes, errors)
  rescue CSV::MalformedCSVError => e
    raise Rates::Error, "The file is not a readable CSV: #{e.message}"
  end

  def self.read(row, filename)
    currency = row["currency"].to_s.strip.upcase
    return [ nil, "EUR is the reference: it has no rate" ] if currency == "EUR"
    return [ nil, "#{currency.presence || '(none)'} is not a currency code" ] unless currency.match?(/\A[A-Z]{3}\z/)

    date = Date.iso8601(row["date"].to_s.strip)
    rate = BigDecimal(row["rate"].to_s.strip.tr(",", "."))
    return [ nil, "The rate must be positive (got #{row['rate']})" ] unless rate.positive?

    type = (row["type"].presence || "daily").to_s.strip.to_sym
    return [ nil, "Unknown type #{type}" ] unless Accounting::ExchangeRate.rate_types.key?(type.to_s)

    [ Rates::Quote.new(currency: currency, date: date, rate: rate, type: type, source: "csv:#{filename}"), nil ]
  rescue Date::Error
    [ nil, "The date #{row['date'].inspect} is not a date (use 2026-09-30)" ]
  rescue ArgumentError
    [ nil, "The rate #{row['rate'].inspect} is not a number" ]
  end
  private_class_method :read
end
