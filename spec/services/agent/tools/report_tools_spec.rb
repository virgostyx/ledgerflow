require "rails_helper"

# The report tools: trial balance, ledger, aged balance, open lines. Each one is checked against the report it wraps, for the same filters (parity), then on what the agent adds:
# the limits, the cursor, the warnings and the references.
RSpec.describe "The report tools of the agent" do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:today) { Date.current }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: today) }
  let(:registry) { Agent::ToolRegistry.new([ Agent::Tools::GetTrialBalance, Agent::Tools::GetLedger, Agent::Tools::GetAgedBalance, Agent::Tools::ListUnreconciled ]) }
  let(:sales) { create(:journal, :sale) }

  let!(:customers) { create(:account, :customer, reconcilable: true) }
  let!(:revenue)   { create(:account, code: "700000", label_fr: "Ventes", account_type: :revenue, normal_balance: :credit) }
  let(:alice) { create(:partner, name: "Alice SA") }
  let(:bob)   { create(:partner, name: "Bob SRL") }

  def run(name, args) = registry.execute(name, args, context)

  def invoice_to(partner, amount, days_ago:, due_days_ago:)
    entry = create(:journal_entry, :draft, journal: sales, fiscal_year: fiscal_year, entry_date: today - days_ago)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    invoice = create(:invoice, :posted, fiscal_year: fiscal_year, due_date: today - due_days_ago)
    create(:journal_entry_line, journal_entry: entry, account: customers, partner: partner, invoice: invoice, debit: BigDecimal(amount), credit: 0, label: "Invoice #{partner.name}")
    create(:journal_entry_line, journal_entry: entry, account: revenue, debit: 0, credit: BigDecimal(amount))
    entry.post!
    entry
  end

  let!(:alice_entry) { invoice_to(alice, "100.00", days_ago: 45, due_days_ago: 40) }
  let!(:bob_entry)   { invoice_to(bob, "300.50", days_ago: 10, due_days_ago: 5) }

  describe Agent::Tools::GetTrialBalance do
    let(:tool) { described_class }
    let(:valid_args) { {} }

    it_behaves_like "an agent tool", permission: "reports.view"

    it "gives what the report gives, account by account, with the amounts as strings" do
      rows = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: today).call
      result = run("get_trial_balance", {})

      expect(result["data"].map { |r| r["code"] }).to eq(rows.map(&:code))
      customer = result["data"].find { |r| r["code"] == customers.code }
      expected = rows.find { |r| r.code == customers.code }
      expect(customer).to include("movement_debit" => "400.50", "closing_debit" => Agent::ToolResult.money(expected.closing_display_debit), "closing_credit" => "0.00")
      expect(result["totals"]).to include("closing_debit" => "400.50", "closing_credit" => "400.50")
    end

    it "says validated entries only, and that the year is not closed" do
      result = run("get_trial_balance", {})

      expect(result["filters_applied"]).to include("entries" => "validated only", "fiscal_year" => fiscal_year.year)
      expect(result["warnings"].join).to include("not closed")
    end

    it "narrows to a family of accounts, and totals only what it shows" do
      result = run("get_trial_balance", { "account_prefix" => "40" })

      expect(result["data"].map { |r| r["code"] }).to eq([ customers.code ])
      expect(result["totals"]).to include("movement_debit" => "400.50", "movement_credit" => "0.00")
    end

    it "reads a past date: what was booked after it is not in" do
      result = run("get_trial_balance", { "as_of" => (today - 20).iso8601 })

      expect(result["totals"]["movement_debit"]).to eq("100.00")
    end

    it "gives the references of the ledger of each account and of the report" do
      result = run("get_trial_balance", { "account_prefix" => "40" })

      expect(result["data"].first["ref"]).to start_with("R02:#{fiscal_year.id}:#{customers.id}:")
      expect(result["totals"]["ref"]).to eq("R01:#{fiscal_year.id}:#{today.iso8601}")
    end

    it "pages by account" do
      first = run("get_trial_balance", { "limit" => 1 })

      expect(first["data"].size).to eq(1)
      expect(first["next_cursor"]).to be_present
      expect(run("get_trial_balance", { "limit" => 1, "cursor" => first["next_cursor"] })["data"].map { |r| r["code"] }).not_to include(first["data"].first["code"])
    end

    it "refuses a period that ends before it starts, and a fiscal year that does not exist" do
      expect(run("get_trial_balance", { "date_from" => today.iso8601, "as_of" => (today - 1).iso8601 })).to include("error" => "invalid_arguments")
      expect(run("get_trial_balance", { "fiscal_year" => 1999 })).to include("error" => "not_found")
    end
  end

  describe Agent::Tools::GetLedger do
    let(:tool) { described_class }
    let(:valid_args) { { "account" => customers.code } }

    it_behaves_like "an agent tool", permission: "reports.view"

    it "gives the ledger of the account as the report does: lines, running balance, totals" do
      query = Accounting::GeneralLedgerQuery.new(account: customers, fiscal_year: fiscal_year)
      lines = query.call
      result = run("get_ledger", { "account" => customers.code })

      expect(result["data"].map { |l| l["running_balance"] }).to eq(lines.map { |l| Agent::ToolResult.money(l.running_balance) })
      expect(result["data"].map { |l| l["reference"] }).to eq(lines.map(&:reference))
      expect(result["totals"]).to include("opening_balance" => "0.00", "debit" => "400.50", "credit" => "0.00", "closing_balance" => "400.50")
      expect(result["filters_applied"]).to include("account" => customers.code, "entries" => "validated only")
    end

    it "narrows to a partner" do
      result = run("get_ledger", { "account" => customers.code, "partner_id" => alice.id })

      expect(result["data"].map { |l| l["partner"] }).to eq([ "Alice SA" ])
      expect(result["totals"]["debit"]).to eq("100.00")
    end

    it "narrows to a period, the part before it becoming the opening balance" do
      result = run("get_ledger", { "account" => customers.code, "date_from" => (today - 20).iso8601 })

      expect(result["totals"]).to include("opening_balance" => "100.00", "debit" => "300.50", "closing_balance" => "400.50")
    end

    it "points each line at its entry" do
      expect(run("get_ledger", { "account" => customers.code })["data"].map { |l| l["ref"] }).to eq([ "entry:#{alice_entry.id}", "entry:#{bob_entry.id}" ])
    end

    it "says there is no such account, or partner, or journal" do
      expect(run("get_ledger", { "account" => "999999" })).to include("error" => "not_found")
      expect(run("get_ledger", { "account" => customers.code, "partner_id" => 0 + 999_999 })).to include("error" => "not_found")
      expect(run("get_ledger", { "account" => customers.code, "journal" => "NOPE" })).to include("error" => "not_found")
    end

    it "refuses to load an account with more lines than it can handle, and says how to narrow" do
      stub_const("Agent::Tools::GetLedger::MAX_LINES", 1)

      result = run("get_ledger", { "account" => customers.code })

      expect(result).to include("error" => "too_large")
      expect(result["message"]).to include("narrow")
    end

    it "pages through the lines" do
      first = run("get_ledger", { "account" => customers.code, "limit" => 1 })

      expect(first["truncated"]).to be true
      second = run("get_ledger", { "account" => customers.code, "limit" => 1, "cursor" => first["next_cursor"] })
      expect(second["data"].map { |l| l["partner"] }).to eq([ "Bob SRL" ])
      expect(second).not_to include("next_cursor")
    end
  end

  describe Agent::Tools::GetAgedBalance do
    let(:tool) { described_class }
    let(:valid_args) { { "kind" => "customer" } }

    it_behaves_like "an agent tool", permission: "reports.view"

    it "gives the report's rows and totals, biggest first" do
      rows = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: today).call
      result = run("get_aged_balance", { "kind" => "customer" })

      expect(result["data"].map { |r| r["partner"] }).to eq([ "Bob SRL", "Alice SA" ])
      alice_row = rows.find { |r| r.partner_name == "Alice SA" }
      expect(result["data"].last).to include("days_31_60" => Agent::ToolResult.money(alice_row.days_31_60), "total" => "100.00", "overdue" => "100.00", "overdue_percent" => "100.0")
      expect(result["totals"]).to include("total" => "400.50", "days_1_30" => "300.50", "days_31_60" => "100.00", "overdue" => "400.50")
    end

    it "orders by name or by what is overdue when asked, and narrows to one partner" do
      expect(run("get_aged_balance", { "kind" => "customer", "sort" => "name" })["data"].map { |r| r["partner"] }).to eq([ "Alice SA", "Bob SRL" ])
      only = run("get_aged_balance", { "kind" => "customer", "partner_id" => alice.id })

      expect(only["data"].map { |r| r["partner"] }).to eq([ "Alice SA" ])
      expect(only["totals"]["total"]).to eq("100.00")
    end

    it "limits to the top rows by default and says it is partial" do
      result = run("get_aged_balance", { "kind" => "customer", "limit" => 1 })

      expect(result["data"].size).to eq(1)
      expect(result).to include("truncated" => true, "row_count" => 1)
      expect(result["totals"]["total"]).to eq("400.50") # the totals cover every row, not the page
    end

    it "reads suppliers apart from customers" do
      expect(run("get_aged_balance", { "kind" => "supplier" })["data"]).to be_empty
    end

    it "gives each row a reference to the report, filtered as it was asked" do
      expect(run("get_aged_balance", { "kind" => "customer" })["data"].first["ref"]).to eq("R04:#{today.iso8601}:customer:#{bob.id}")
    end

    it "asks for a kind" do
      expect(run("get_aged_balance", {})).to include("error" => "invalid_arguments")
    end
  end

  describe Agent::Tools::ListUnreconciled do
    let(:tool) { described_class }
    let(:valid_args) { { "kind" => "customer" } }

    it_behaves_like "an agent tool", permission: "reports.view"

    it "lists the open lines as the report does, with their age" do
      rows = Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: today).call
      result = run("list_unreconciled", { "kind" => "customer" })

      expect(result["data"].map { |r| r["residual"] }).to eq(rows.map { |r| Agent::ToolResult.money(r.residual) })
      expect(result["data"].map { |r| r["age_days"] }).to eq(rows.map(&:age_days))
      expect(result["totals"]).to include("residual" => "400.50", "lines" => "2")
    end

    it "keeps the lines overdue by at least some days, and those of one partner" do
      expect(run("list_unreconciled", { "kind" => "customer", "min_age_days" => 30 })["data"].map { |r| r["partner"] }).to eq([ "Alice SA" ])
      expect(run("list_unreconciled", { "kind" => "customer", "partner_id" => bob.id })["data"].map { |r| r["partner"] }).to eq([ "Bob SRL" ])
    end

    it "points each line at its entry" do
      expect(run("list_unreconciled", { "kind" => "customer" })["data"].map { |r| r["ref"] }).to contain_exactly("entry:#{alice_entry.id}", "entry:#{bob_entry.id}")
    end
  end
end
