require "rails_helper"

# F11, the sources of rates: the ECB's daily reference rates, InforEuro's monthly rates, a CSV file. Units of currency for 1 EUR in all three.
# The ECB and InforEuro fixtures are real answers, trimmed to a few currencies.
RSpec.describe "Rate providers" do
  def fixture(name) = Rails.root.join("spec/fixtures/rates", name).read

  describe Rates::Ecb do
    it "reads the daily reference rates, as the ECB gives them: units of currency for 1 EUR" do
      stub_request(:get, "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml").to_return(status: 200, body: fixture("ecb_daily.xml"))

      quotes = described_class.daily
      expect(quotes.map { |q| [ q.currency, q.date, q.rate, q.type, q.source ] }).to contain_exactly(
        [ "USD", Date.new(2026, 10, 2), BigDecimal("1.1225"), :daily, "ecb" ],
        [ "JPY", Date.new(2026, 10, 2), BigDecimal("176.99"), :daily, "ecb" ],
        [ "GBP", Date.new(2026, 10, 2), BigDecimal("0.85033"), :daily, "ecb" ]
      )
    end

    it "reads the history of the last 90 days, whatever the quoting and spacing of the XML" do
      stub_request(:get, "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml").to_return(status: 200, body: fixture("ecb_hist.xml"))

      quotes = described_class.history
      expect(quotes.map(&:date).uniq).to contain_exactly(Date.new(2026, 10, 2), Date.new(2026, 10, 1))
      expect(quotes.size).to eq(6)
      expect(quotes.find { |q| q.currency == "USD" && q.date == Date.new(2026, 10, 1) }.rate).to eq(BigDecimal("1.1298"))
    end

    it "fails with a message that names the source when the answer is not 200" do
      stub_request(:get, %r{eurofxref-daily}).to_return(status: 503)
      expect { described_class.daily }.to raise_error(Rates::Error, /ECB.*503/)
    end

    it "fails when the answer is not the XML expected" do
      stub_request(:get, %r{eurofxref-daily}).to_return(status: 200, body: "<html>maintenance</html>")
      expect { described_class.daily }.to raise_error(Rates::Error, /ECB/)
    end

    it "fails when the network does", :aggregate_failures do
      stub_request(:get, %r{eurofxref-daily}).to_timeout
      expect { described_class.daily }.to raise_error(Rates::Error, /ECB/)
    end
  end

  describe Rates::InforEuro do
    it "reads the monthly rates, dated the first of the month, and leaves the euro out" do
      stub_request(:get, "https://ec.europa.eu/budg/inforeuro/api/public/monthly-rates").with(query: { lang: "EN", year: "2026", month: "9" })
        .to_return(status: 200, body: fixture("inforeuro_month.json"))

      quotes = described_class.month(2026, 9)
      expect(quotes.map { |q| [ q.currency, q.date, q.type, q.source ] }).to all(satisfy { |c, d, t, s| d == Date.new(2026, 9, 1) && t == :monthly_average && s == "inforeuro" })
      expect(quotes.map(&:currency)).to contain_exactly("USD", "GBP", "ZMW", "JPY")
      expect(quotes.find { |q| q.currency == "ZMW" }.rate).to eq(BigDecimal("22.2019"))
    end

    it "says when a month is not published yet" do
      stub_request(:get, %r{inforeuro}).to_return(status: 404, body: { code: 5, exception: "Exception", message: "No rates published for period 2026/13" }.to_json)
      expect { described_class.month(2026, 13) }.to raise_error(Rates::NotPublished, /2026\/13/)
    end

    it "fails with the source in the message on any other error" do
      stub_request(:get, %r{inforeuro}).to_return(status: 500, body: "boom")
      expect { described_class.month(2026, 9) }.to raise_error(Rates::Error, /InforEuro.*500/)
    end
  end

  describe Rates::Csv do
    it "reads currency, date and rate, with a decimal point or comma, and the kind when given" do
      csv = "currency,date,rate,type\nusd,2026-09-30,\"1,0912\",daily\nZMW,2026-09-30,22.5,closing\nGBP,2026-09-30,0.85,\n"
      result = described_class.parse(csv, filename: "rates.csv")

      expect(result.errors).to eq([])
      expect(result.quotes.map { |q| [ q.currency, q.date, q.rate, q.type, q.source ] }).to eq([
        [ "USD", Date.new(2026, 9, 30), BigDecimal("1.0912"), :daily, "csv:rates.csv" ],
        [ "ZMW", Date.new(2026, 9, 30), BigDecimal("22.5"), :closing, "csv:rates.csv" ],
        [ "GBP", Date.new(2026, 9, 30), BigDecimal("0.85"), :daily, "csv:rates.csv" ]
      ])
    end

    it "keeps the good rows and names each bad one by its line: zero, negative, not a number, unknown date, unknown kind (the edge cases)" do
      csv = "currency,date,rate\nUSD,2026-09-30,0\nUSD,2026-09-29,-1.1\nUSD,2026-09-28,abc\nUSD,not-a-date,1.1\nEUR,2026-09-30,1\nUSD,2026-09-27,1.09\n"
      result = described_class.parse(csv, filename: "r.csv")

      expect(result.quotes.map(&:rate)).to eq([ BigDecimal("1.09") ])
      expect(result.errors.map(&:first)).to eq([ 2, 3, 4, 5, 6 ])
      expect(result.errors.map(&:last).join(" ")).to match(/positive/i).and match(/date/i).and match(/EUR/)
    end

    it "refuses a file without the three columns" do
      expect { described_class.parse("a,b\n1,2\n", filename: "x.csv") }.to raise_error(Rates::Error, /currency, date, rate/)
    end
  end
end
