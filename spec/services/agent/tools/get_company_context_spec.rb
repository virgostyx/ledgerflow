require "rails_helper"

RSpec.describe Agent::Tools::GetCompanyContext do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: Date.new(2026, 9, 26)) }
  let(:registry) { Agent::ToolRegistry.new([ described_class ]) }
  let(:tool) { described_class }
  let(:valid_args) { {} }

  it_behaves_like "an agent tool", permission: "agent.use", denied_role: :auditor

  it "describes the entity, its fiscal years with the current one, and its journals" do
    create(:journal, :purchase, code: "ACH")
    past = create(:fiscal_year, year: fiscal_year.year - 1, status: :closed, entity: entity, start_date: fiscal_year.start_date - 1.year, end_date: fiscal_year.end_date - 1.year)

    row = registry.execute("get_company_context", {}, context)["data"].first

    expect(row["entity"]).to include("name" => entity.name, "country" => entity.country)
    expect(row["fiscal_years"].map { |y| [ y["year"], y["status"], y["current"] ] }).to eq([ [ past.year, "closed", false ], [ fiscal_year.year, "open", true ] ])
    expect(row["journals"].map { |j| j["code"] }).to include("ACH")
  end

  it "lists the periods that are locked, not those that were unlocked" do
    admin = create(:user)
    Accounting::PeriodLock.create!(kind: :accounting, status: :locked, starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date + 30, locked_by: admin, locked_at: Time.current, entity: entity)

    locked = registry.execute("get_company_context", {}, context)["data"].first["locked_periods"]

    expect(locked).to eq([ { "kind" => "accounting", "starts_on" => fiscal_year.start_date.iso8601, "ends_on" => (fiscal_year.start_date + 30).iso8601 } ])
  end

  it "stands at the day of the context" do
    expect(registry.execute("get_company_context", {}, context)["as_of"]).to eq("2026-09-26")
  end
end
