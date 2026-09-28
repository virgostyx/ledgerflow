require "rails_helper"

RSpec.describe Reports::ChartComponent, type: :component do
  it "mounts the chart controller with the option as JSON and an accessible label" do
    render_inline(described_class.new(option: { series: [ { data: [ 1, 2 ] } ] }, title: "Cash", height: 120))
    node = page.find("div[data-controller='chart']")
    expect(node["role"]).to eq("img")
    expect(node["aria-label"]).to eq("Cash")
    expect(JSON.parse(node["data-chart-option-value"])["series"].first["data"]).to eq([ 1, 2 ])
    expect(node["data-chart-height-value"]).to eq("120")
  end
end
