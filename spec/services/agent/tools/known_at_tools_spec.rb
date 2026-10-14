require "rails_helper"

# B03a §"Agent IA": the report tools take `known_at`; an answer built on a past instant says "state known at ..."; the feature and the right are needed; an instant before the
# history is refused.
RSpec.describe "The report tools of the agent, as known at an instant" do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: Date.current) }
  let(:registry) { Agent::ToolRegistry.default }
  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_entry(amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: "A-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
  end

  def run(name, args) = registry.execute(name, args, context)

  before do
    post_entry(BigDecimal("100"))
    @at = instant
    post_entry(BigDecimal("50"))
  end

  it "gives the trial balance as it was known, and says so" do
    past = run("get_trial_balance", { "account_prefix" => "604", "known_at" => @at.utc.iso8601(6) })
    today = run("get_trial_balance", { "account_prefix" => "604" })

    expect(past["data"].sole["closing_debit"]).to eq("100.00")
    expect(today["data"].sole["closing_debit"]).to eq("150.00")
    expect(past["warnings"].join).to include("State known at")
    expect(past["filters_applied"]["known_at"]).to be_present
    expect(today["warnings"].join).not_to include("State known at")
  end

  it "gives the ledger, the statements and the VAT grids as they were known" do
    ledger = run("get_ledger", { "account" => "604000", "known_at" => @at.utc.iso8601(6) })
    expect(ledger["data"].size).to eq(1)
    expect(ledger["warnings"].join).to include("State known at")

    statements = run("get_financial_statements", { "statement" => "income", "known_at" => @at.utc.iso8601(6) })
    expect(statements["warnings"].join).to include("State known at")

    vat = run("get_vat_return", { "period_start" => fiscal_year.start_date.iso8601, "period_end" => fiscal_year.end_date.iso8601, "known_at" => @at.utc.iso8601(6) })
    expect(vat["warnings"].join).to include("State known at")
  end

  it "gives the aged balance as it was known" do
    expect(run("get_aged_balance", { "kind" => "customer", "known_at" => @at.utc.iso8601(6) })["warnings"].join).to include("State known at")
  end

  it "refuses an instant before the history, an instant that is not one, and the feature off" do
    expect(run("get_trial_balance", { "known_at" => 3.days.ago.utc.iso8601 })).to include("error" => "invalid_arguments")
    expect(run("get_trial_balance", { "known_at" => "yesterday" })).to include("error" => "invalid_arguments")

    entity.update!(features: entity.features.merge("b03a" => false))
    expect(run("get_trial_balance", { "known_at" => @at.utc.iso8601 })).to include("error" => "forbidden")
  end

  it "is today's view for an instant that is now or later" do
    result = run("get_trial_balance", { "account_prefix" => "604", "known_at" => 1.hour.from_now.utc.iso8601 })

    expect(result["data"].sole["closing_debit"]).to eq("150.00")
    expect(result["warnings"].join).not_to include("State known at")
  end
end
