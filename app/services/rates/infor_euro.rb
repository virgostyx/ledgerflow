require "json"

# The European Commission's InforEuro monthly rates (F11): units of currency for 1 EUR, one rate per currency and month, which the Commission asks
# its beneficiaries to use for their reports (R11). Dated the first of the month. Covers currencies the ECB does not (the Zambian kwacha).
class Rates::InforEuro
  URL    = "https://ec.europa.eu/budg/inforeuro/api/public/monthly-rates".freeze
  SOURCE = "inforeuro".freeze

  def self.month(year, month)
    body = Rates::Http.get("#{URL}?lang=EN&year=#{year}&month=#{month}", source: "InforEuro") do |response|
      raise Rates::NotPublished, JSON.parse(response.body)["message"].to_s if response.code == "404"
    end
    JSON.parse(body).filter_map do |row|
      next if row["isoA3Code"] == "EUR"

      Rates::Quote.new(currency: row["isoA3Code"], date: Date.new(year, month, 1), rate: BigDecimal(row["value"].to_s), type: :monthly_average, source: SOURCE)
    end
  rescue JSON::ParserError, TypeError, ArgumentError
    raise Rates::Error, "InforEuro sent something that is not the monthly rates"
  end
end
