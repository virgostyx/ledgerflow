require "rails_helper"

RSpec.describe Reports::Result, type: :model do
  it "carries rows, totals and filters, with sensible defaults" do
    result = described_class.new(rows: [ 1, 2, 3 ], filters: Reports::Filters.new)

    expect(result.rows).to eq([ 1, 2, 3 ])
    expect(result.totals).to eq({})
    expect(result.currency).to eq("EUR")
    expect(result.warnings).to eq([])
    expect(result.generated_at).to be_within(1.second).of(Time.current)
  end

  it "is immutable" do
    result = described_class.new(rows: [])
    expect { result.rows = [ 1 ] }.to raise_error(NoMethodError)
  end
end
