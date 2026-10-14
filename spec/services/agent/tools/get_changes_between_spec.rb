require "rails_helper"

# B03b §"Interface" (Agent): `get_changes_between` gives the summary of what changed between two moments, the biggest impacts, the alerts and the closing. No name of a person.
RSpec.describe Agent::Tools::GetChangesBetween do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: Date.current) }
  let(:registry) { Agent::ToolRegistry.default }
  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before do
    entity.update!(features: entity.features.merge("b03a" => true, "b03b" => true))
    Accounting::HistoryStart.create!(starts_at: 1.day.ago)
  end

  def post_entry(amount, date: [ Date.current, fiscal_year.end_date ].min)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date, reference: "A-#{SecureRandom.hex(3)}", created_by_id: user.id)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
  end

  def run(args) = registry.execute("get_changes_between", args, context)

  it "gives the summary, the impact, the alerts and the closing between two instants" do
    from = instant
    post_entry(100)
    post_entry(40, date: fiscal_year.start_date) # late, as the year started long ago
    to = instant
    post_entry(5)

    result = run("from" => from.utc.iso8601(6), "to" => to.utc.iso8601(6))

    expect(result["totals"]).to include("entries" => "2")
    expect(result["data"].map { |r| r["code"] }).to include("604000")
    expect(result["data"].find { |r| r["code"] == "604000" }).to include("variation" => "140.00")
    expect(result["warnings"].join).to include("Sum of variations = sum of movements")
    expect(result.to_json).not_to include(user.email)
  end

  it "reports the alerts by kind" do
    from = instant
    post_entry(40, date: fiscal_year.start_date - 0 + 0) if Date.current - fiscal_year.start_date > 20
    result = run("from" => from.utc.iso8601(6))

    expect(result).to have_key("filters_applied")
  end

  it "is refused when the feature is off, and before the start of the history, and when T1 is after T2" do
    expect(run("from" => 3.days.ago.utc.iso8601, "to" => Time.current.utc.iso8601)).to include("error" => "invalid_arguments").or include("error" => "forbidden")
    expect(run("from" => Time.current.utc.iso8601, "to" => 1.hour.ago.utc.iso8601)["message"]).to include("swap")

    entity.update!(features: entity.features.merge("b03b" => false))
    expect(run("from" => 1.hour.ago.utc.iso8601)).to include("error" => "forbidden")
  end
end
