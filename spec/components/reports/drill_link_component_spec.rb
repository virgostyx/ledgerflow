require "rails_helper"

RSpec.describe Reports::DrillLinkComponent, type: :component do
  let(:filters) { Reports::Filters.new(fiscal_year_id: 3, date_from: "2026-01-01") }

  it "links to the target path, carrying the current filters in the query string" do
    render_inline(described_class.new(path: "/accounting/reports/general_ledger", filters: filters, text: "600000"))

    link = page.find_link("600000")
    query = Rack::Utils.parse_nested_query(link[:href].split("?").last)
    expect(link[:href]).to start_with("/accounting/reports/general_ledger?")
    expect(query).to include("fiscal_year_id" => "3", "date_from" => "2026-01-01")
  end

  it "overrides individual filters for the drilled-down target (e.g. one account, not the whole range)" do
    render_inline(described_class.new(path: "/accounting/reports/general_ledger", filters: filters,
                                       text: "600000", overrides: { account_from: "600000", account_to: "600000" }))

    query = Rack::Utils.parse_nested_query(page.find_link("600000")[:href].split("?").last)
    expect(query).to include("account_from" => "600000", "account_to" => "600000", "fiscal_year_id" => "3")
  end
end
