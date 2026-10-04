require "rails_helper"

RSpec.describe "Accounting::Settings::ExchangeRates", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)    { create(:user, role: :manager) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager, user: manager, entity: entity) }

  before { sign_in accountant }

  it "lists, creates and deletes rates" do
    get accounting_settings_exchange_rates_path
    expect(response).to have_http_status(:ok)

    expect {
      post accounting_settings_exchange_rates_path,
           params: { accounting_exchange_rate: { currency: "usd", rate_date: "2026-09-30", rate: "0,9512", reason: "Bank statement rate" } }
    }.to change(Accounting::ExchangeRate, :count).by(1)
    rate = Accounting::ExchangeRate.last
    expect([ rate.currency, rate.rate ]).to eq([ "USD", BigDecimal("0.9512") ])

    get accounting_settings_exchange_rates_path
    expect(response.body).to include("USD", "0.9512")

    expect { delete accounting_settings_exchange_rate_path(rate) }.to change(Accounting::ExchangeRate, :count).by(-1)
  end

  it "shows the error when the rate is invalid" do
    expect {
      post accounting_settings_exchange_rates_path,
           params: { accounting_exchange_rate: { currency: "EUR", rate_date: "2026-09-30", rate: "1", reason: "x" } }
    }.not_to change(Accounting::ExchangeRate, :count)
    expect(flash[:alert]).to be_present
  end

  it "is refused to a manager" do
    sign_in manager
    get accounting_settings_exchange_rates_path
    expect(response).to redirect_to(accounting_root_path)
  end
end

# F11: the screen keeps what it did and adds the kinds and sources of the rates, the rules of the entity, the imports and the missing rates.
RSpec.describe "Exchange rates, rules and imports (F11)", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let(:today) { Date.current }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }

  def fixture(name) = Rails.root.join("spec/fixtures/rates", name).read

  before { sign_in accountant }

  describe "the list" do
    it "shows the kind, the source and the date of import of each rate, and filters by currency and kind" do
      Accounting::ExchangeRate.create!(currency: "USD", rate_date: today, rate: "1.12345678", rate_type: :daily, source: "ecb", imported_at: Time.current)
      Accounting::ExchangeRate.create!(currency: "ZMW", rate_date: today, rate: "22.2", rate_type: :monthly_average, source: "inforeuro")

      get accounting_settings_exchange_rates_path
      expect(response.body).to include("1.12345678", "ecb", "Daily", "Monthly average", "inforeuro")

      get accounting_settings_exchange_rates_path, params: { currency: "ZMW" }
      expect(response.body).to include("22.2").and not_include("1.12345678")
      get accounting_settings_exchange_rates_path, params: { rate_type: "daily" }
      expect(response.body).to include("1.12345678").and not_include("22.2")
    end

    it "says in units of currency for 1 EUR" do
      get accounting_settings_exchange_rates_path
      expect(response.body).to include("for 1 EUR")
    end

    it "warns of the working days without a rate, for a currency in use" do
      create(:partner, currency: "USD")
      get accounting_settings_exchange_rates_path
      expect(response.body).to include('data-section="missing-rates"', "USD")
    end
  end

  describe "typing a rate by hand" do
    it "takes the kind, and needs a reason, as before" do
      post accounting_settings_exchange_rates_path, params: { accounting_exchange_rate: { currency: "USD", rate_date: today.iso8601, rate: "1,1", rate_type: "closing", reason: "Closing rate of the bank" } }
      expect(Accounting::ExchangeRate.sole).to have_attributes(rate_type: "closing", source: "manual", created_by: accountant)

      post accounting_settings_exchange_rates_path, params: { accounting_exchange_rate: { currency: "USD", rate_date: (today - 1).iso8601, rate: "1.1", rate_type: "manual", reason: "" } }
      expect(flash[:alert]).to match(/reason/i)
    end

    it "is refused to someone who may not override rates" do
      sign_in assistant
      expect { post accounting_settings_exchange_rates_path, params: { accounting_exchange_rate: { currency: "USD", rate_date: today.iso8601, rate: "1.1", rate_type: "manual", reason: "x" } } }
        .not_to change(Accounting::ExchangeRate, :count)
    end

    it "refuses a rate of zero or less" do
      post accounting_settings_exchange_rates_path, params: { accounting_exchange_rate: { currency: "USD", rate_date: today.iso8601, rate: "0", rate_type: "manual", reason: "x" } }
      expect(Accounting::ExchangeRate.count).to eq(0)
      expect(flash[:alert]).to be_present
    end
  end

  describe "importing" do
    it "loads the ECB's latest rates now" do
      stub_request(:get, "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml").to_return(status: 200, body: fixture("ecb_daily.xml"))
      post import_ecb_accounting_settings_exchange_rates_path
      expect(Accounting::ExchangeRate.where(source: "ecb").count).to eq(3)
      expect(flash[:notice]).to include("3")
    end

    it "loads the ECB's last 90 days when asked for the history" do
      stub_request(:get, "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml").to_return(status: 200, body: fixture("ecb_hist.xml"))
      post import_ecb_accounting_settings_exchange_rates_path, params: { history: "1" }
      expect(Accounting::ExchangeRate.where(source: "ecb").count).to eq(6)
    end

    it "says when the source cannot be reached, and stores nothing" do
      stub_request(:get, %r{eurofxref-daily}).to_return(status: 503)
      post import_ecb_accounting_settings_exchange_rates_path
      expect(flash[:alert]).to include("ECB")
      expect(Accounting::ExchangeRate.count).to eq(0)
    end

    it "loads the InforEuro rates of a month" do
      stub_request(:get, %r{monthly-rates}).with(query: hash_including("year" => "2026", "month" => "9")).to_return(status: 200, body: fixture("inforeuro_month.json"))
      post import_inforeuro_accounting_settings_exchange_rates_path, params: { month: "2026-09" }
      expect(Accounting::ExchangeRate.where(source: "inforeuro").pluck(:currency)).to include("ZMW")
    end

    it "loads a CSV file, keeps its good lines and names the bad ones" do
      file = Rack::Test::UploadedFile.new(StringIO.new("currency,date,rate\nUSD,2026-09-30,1.09\nUSD,2026-09-29,0\n"), "text/csv", original_filename: "rates.csv")
      post import_csv_accounting_settings_exchange_rates_path, params: { file: file, reason: "Bank rates of September" }

      expect(Accounting::ExchangeRate.sole).to have_attributes(rate: BigDecimal("1.09"), source: "csv:rates.csv")
      expect(flash[:notice]).to include("1 rate")
      expect(flash[:alert]).to include("line 3")
    end

    it "is refused to someone who may not override rates" do
      sign_in assistant
      stub_request(:get, %r{eurofxref-daily}).to_return(status: 200, body: fixture("ecb_daily.xml"))
      post import_ecb_accounting_settings_exchange_rates_path
      expect(Accounting::ExchangeRate.count).to eq(0)
    end
  end

  describe "the rules of the entity" do
    it "changes the rate policy, the date, the alert, the fallback currencies, the accounts and the treatment of unrealized differences" do
      patch rules_accounting_settings_exchange_rates_path, params: { entity: {
        rate_policy: "monthly_average", rate_date_basis: "accounting_date", rate_alert_pct: "3", rate_fallback_currencies: "USD, ZMW",
        fx_realized_as_draft: "1", fx_loss_account_code: "654000", fx_gain_account_code: "754000", fx_unrealized_loss: "expense", fx_unrealized_gain: "defer"
      } }

      expect(entity.reload).to have_attributes(rate_policy: "monthly_average", rate_date_basis: "accounting_date", rate_alert_pct: BigDecimal("3"),
                                               rate_fallback_currencies: %w[USD ZMW], fx_realized_as_draft: true, fx_loss_account_code: "654000",
                                               fx_gain_account_code: "754000", fx_unrealized_gain: "defer")
    end

    it "refuses an unknown fallback currency, with the reason" do
      patch rules_accounting_settings_exchange_rates_path, params: { entity: { rate_fallback_currencies: "USD, XYZ" } }
      expect(flash[:alert]).to include("XYZ")
      expect(entity.reload.rate_fallback_currencies).to eq([])
    end

    it "shows the rules" do
      get accounting_settings_exchange_rates_path
      expect(response.body).to include("Rate policy", "Fallback", "Unrealized")
    end
  end
end
