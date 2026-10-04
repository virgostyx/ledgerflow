require "rails_helper"

# F11: a scheduled job loads the rates of the entities that turned the feature on. No posting ever goes to the network: only this does.
RSpec.describe Rates::ImportJob do
  def fixture(name) = Rails.root.join("spec/fixtures/rates", name).read

  let!(:on)  { create(:entity, features: Entity::FEATURES.index_with { |f| f == "f11" }) }
  let!(:off) { create(:entity, features: Entity::FEATURES.index_with { false }) }

  # Entities left over by other specs (a shared context creates its entity outside the cleaning transaction) must not take part.
  before { Entity.where.not(id: [ on.id, off.id ]).update_all(features: {}) }

  def stub_sources(ecb: 200, infor: 200)
    stub_request(:get, "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml").to_return(status: ecb, body: fixture("ecb_daily.xml"))
    stub_request(:get, %r{inforeuro/api/public/monthly-rates}).to_return(status: infor, body: infor == 200 ? fixture("inforeuro_month.json") : { code: 5, message: "No rates published for period" }.to_json)
  end

  def rates_of(entity) = ActsAsTenant.with_tenant(entity) { Accounting::ExchangeRate.pluck(:currency, :rate_type, :source).sort }

  it "loads the ECB daily rates and the InforEuro monthly rates for an entity that turned the feature on, and for no other" do
    stub_sources
    described_class.perform_now

    expect(rates_of(on)).to include([ "USD", "daily", "ecb" ], [ "ZMW", "monthly_average", "inforeuro" ])
    expect(rates_of(off)).to eq([])
  end

  it "does it again without making a second row" do
    stub_sources
    described_class.perform_now
    expect { described_class.perform_now }.not_to(change { rates_of(on).size })
  end

  it "takes the InforEuro rates of this month and of the last one" do
    stub_sources
    travel_to(Date.new(2026, 10, 15)) { described_class.perform_now }
    expect(a_request(:get, %r{monthly-rates}).with(query: hash_including("year" => "2026", "month" => "10"))).to have_been_made
    expect(a_request(:get, %r{monthly-rates}).with(query: hash_including("year" => "2026", "month" => "9"))).to have_been_made
  end

  it "goes on with InforEuro when the ECB is down, and does not raise" do
    stub_sources(ecb: 503)
    expect { described_class.perform_now }.not_to raise_error
    expect(rates_of(on).map(&:last)).to all(eq("inforeuro"))
  end

  it "takes a month that is not published yet for no error" do
    stub_sources(infor: 404)
    expect { described_class.perform_now }.not_to raise_error
    expect(rates_of(on).map(&:last)).to all(eq("ecb"))
  end
end
