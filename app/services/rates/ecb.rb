require "nokogiri"

# The European Central Bank's euro foreign exchange reference rates (F11): published each working day around 16:00 CET, units of currency for 1 EUR,
# the convention of the application. `daily` is the last day; `history` the last 90 days (to fill a gap). The ECB gives about thirty currencies.
class Rates::Ecb
  DAILY   = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml".freeze
  HISTORY = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml".freeze
  SOURCE  = "ecb".freeze

  def self.daily   = read(DAILY)
  def self.history = read(HISTORY)

  def self.read(url)
    doc = Nokogiri::XML(Rates::Http.get(url, source: "ECB"))
    days = doc.remove_namespaces!.xpath("//Cube[@time]")
    raise Rates::Error, "ECB sent something that is not the reference rates" if days.empty?

    days.flat_map do |day|
      date = Date.iso8601(day["time"])
      day.xpath("Cube[@currency]").map do |c|
        Rates::Quote.new(currency: c["currency"], date: date, rate: BigDecimal(c["rate"]), type: :daily, source: SOURCE)
      end
    end
  rescue Date::Error, ArgumentError
    raise Rates::Error, "ECB sent something that is not the reference rates"
  end
  private_class_method :read
end
