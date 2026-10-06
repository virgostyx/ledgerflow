require "rails_helper"

# The remaining read tools: bank reconciliation, annual accounts, VAT grids, dashboard indicators, consistency findings, audit trail, documents. Each is checked against the
# report or the model it wraps, then on what the agent adds.
RSpec.describe "The other read tools of the agent" do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:today) { Date.current }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: today) }
  let(:registry) do
    Agent::ToolRegistry.new([ Agent::Tools::GetBankReconciliation, Agent::Tools::GetFinancialStatements, Agent::Tools::GetVatReturn, Agent::Tools::GetDashboardKpis,
                              Agent::Tools::GetConsistencyFindings, Agent::Tools::GetAuditTrail, Agent::Tools::SearchDocuments ])
  end

  def run(name, args) = registry.execute(name, args, context)

  let(:vat_journal) { create(:journal, :purchase) }
  let(:vat_account) { create(:account, code: "451000", label_fr: "TVA") }

  def post_vat_entry(vat_code:, vat_amount:, debit_side: true, date: today)
    journal = vat_journal
    account = vat_account
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account, debit: debit_side ? 1000 : 0, credit: debit_side ? 0 : 1000, vat_code: vat_code, vat_amount: BigDecimal(vat_amount))
    entry.post!
    entry
  end

  describe Agent::Tools::GetBankReconciliation do
    let(:tool) { described_class }
    let!(:bank) { create(:bank_account, label_fr: "ING courant") }
    let(:valid_args) { { "journal" => bank.journal.code } }

    before do
      bank.journal.update!(default_account: create(:account, code: "550000", account_class: 5))
      create(:bank_transaction, bank_account: bank, amount: BigDecimal("250.00"), transaction_date: today - 3, description: "Virement client")
    end

    it_behaves_like "an agent tool", permission: "reports.view"

    it "gives what the report gives: balances, what is on the statement and not booked, the gap" do
      expected = Accounting::BankReconciliationQuery.new(bank_account: bank, as_of: today).call
      row = run("get_bank_reconciliation", { "journal" => bank.journal.code })["data"].first

      expect(row).to include("bank_account" => "ING courant", "currency" => "EUR", "statement_balance" => Agent::ToolResult.money(expected.statement_balance),
                             "accounting_balance" => Agent::ToolResult.money(expected.accounting_balance), "gap" => Agent::ToolResult.money(expected.gap),
                             "on_statement_not_booked_total" => Agent::ToolResult.money(expected.sn_total))
      expect(row["on_statement_not_booked"].map { |i| i["amount"] }).to eq(expected.sn.map { |i| Agent::ToolResult.money(i.amount) })
    end

    it "takes the only bank account when none is named, and lists the choices when there are several" do
      expect(run("get_bank_reconciliation", {})["data"].first["bank_account"]).to eq("ING courant")

      second = create(:bank_account, label_fr: "KBC épargne")
      second.journal.update!(default_account: create(:account, code: "551000", account_class: 5))
      answer = run("get_bank_reconciliation", {})

      expect(answer).to include("error" => "invalid_arguments")
      expect(answer["message"]).to include(bank.journal.code, "KBC épargne")
    end

    it "never gives the account number" do
      expect(run("get_bank_reconciliation", { "journal" => bank.journal.code }).to_json).not_to include(bank.iban)
    end
  end

  describe Agent::Tools::GetFinancialStatements do
    let(:tool) { described_class }
    let(:valid_args) { { "statement" => "income" } }

    before do
      sales = create(:journal, :sale)
      customers = create(:account, :customer, reconcilable: true)
      revenue = create(:account, code: "700000", label_fr: "Ventes", account_type: :revenue, normal_balance: :credit)
      entry = create(:journal_entry, :draft, journal: sales, fiscal_year: fiscal_year, entry_date: today)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: customers, partner: create(:partner), debit: 500, credit: 0)
      create(:journal_entry_line, journal_entry: entry, account: revenue, debit: 0, credit: 500)
      entry.post!
    end

    it_behaves_like "an agent tool", permission: "reports.view"

    it "gives the headings and amounts of the report, as strings, with the variation against the previous year" do
      report = Accounting::AnnualAccounts.new(fiscal_year: fiscal_year).call
      rows = run("get_financial_statements", { "statement" => "income", "limit" => 100 })["data"]

      expect(rows.map { |r| r["code"] }).to eq(report.rows(:income).map(&:code))
      expect(rows.map { |r| r["amount"] }).to eq(report.rows(:income).map { |r| Agent::ToolResult.money(r.amount) })
      expect(rows.find { |r| r["amount"] == "500.00" }).to be_present
    end

    it "reads the balance sheet in two parts and says whether it balances" do
      assets = run("get_financial_statements", { "statement" => "assets", "limit" => 100 })

      expect(assets["totals"]).to include("balanced" => "true", "balance_sheet_difference" => "0.00")
      expect(assets["filters_applied"]).to include("statement" => "assets", "fiscal_year" => fiscal_year.year)
    end

    it "warns that a year that is not closed can still move" do
      expect(run("get_financial_statements", { "statement" => "income" })["warnings"].join).to include("not closed")
    end

    it "asks which statement" do
      expect(run("get_financial_statements", {})).to include("error" => "invalid_arguments")
    end
  end

  describe Agent::Tools::GetVatReturn do
    let(:tool) { described_class }
    let(:from) { fiscal_year.start_date }
    let(:to)   { fiscal_year.start_date + 89 }
    let(:valid_args) { { "period_start" => from.iso8601, "period_end" => to.iso8601 } }

    before do
      post_vat_entry(vat_code: 1, vat_amount: "210.00", date: from + 10)
      post_vat_entry(vat_code: 1, vat_amount: "105.00", date: from + 20)
    end

    it_behaves_like "an agent tool", permission: "reports.view"

    it "gives each grid with the amount the report computes" do
      expected = Accounting::VatGridQuery.call(fiscal_year_id: fiscal_year.id, period_start: from, period_end: to)
      result = run("get_vat_return", valid_args)

      expect(result["data"].to_h { |r| [ r["grid"], r["amount"] ] }).to eq(expected.transform_values { |v| Agent::ToolResult.money(v) })
      expect(result["data"].find { |r| r["grid"] == "01" }["amount"]).to eq("315.00")
    end

    it "leaves out what is outside the period" do
      result = run("get_vat_return", { "period_start" => (to + 1).iso8601, "period_end" => (to + 30).iso8601 })

      expect(result["data"]).to be_empty
      expect(result["warnings"].join).to include("No VAT movement")
    end

    it "lists the declarations already prepared for the period, with their status" do
      declaration = create(:vat_declaration, fiscal_year: fiscal_year, period_start: from, period_end: to)

      listed = run("get_vat_return", valid_args)["totals"]["declarations"]

      expect(listed).to eq([ { "period" => "#{from.iso8601}..#{to.iso8601}", "status" => "draft", "ref" => "vat:#{declaration.id}" } ])
    end

    it "refuses a period that ends before it starts" do
      expect(run("get_vat_return", { "period_start" => to.iso8601, "period_end" => from.iso8601 })).to include("error" => "invalid_arguments")
    end
  end

  describe Agent::Tools::GetDashboardKpis do
    let(:tool) { described_class }
    let(:valid_args) { {} }

    it_behaves_like "an agent tool", permission: "reports.view"

    it "gives the indicators of the dashboard with their formula, in the unit of each" do
      cards = Accounting::DashboardKpis.new(fiscal_year: fiscal_year, as_of: today).call
      rows = run("get_dashboard_kpis", {})["data"]

      expect(rows.map { |r| r["key"] }).to eq(cards.map { |c| c.key.to_s })
      expect(rows.find { |r| r["key"] == "cash" }).to include("unit" => "money", "formula" => "Σ balances of accounts 55 and 57", "ref" => "kpi:cash")
    end

    it "gives one indicator when asked, and refuses one that does not exist" do
      expect(run("get_dashboard_kpis", { "kpi" => "dso" })["data"].map { |r| r["key"] }).to eq([ "dso" ])
      expect(run("get_dashboard_kpis", { "kpi" => "happiness" })).to include("error" => "invalid_arguments")
    end
  end

  describe Agent::Tools::GetConsistencyFindings do
    let(:tool) { described_class }
    let(:valid_args) { {} }
    let!(:run_record) { Accounting::ConsistencyRun.create!(started_at: Time.current, finished_at: Time.current, trigger: "manual") }

    def finding(check:, severity:, fingerprint:, message: "An anomaly")
      Accounting::ConsistencyFinding.create!(run: run_record, check_id: check, severity: severity, fingerprint: fingerprint, subject_type: "Accounting::Account", subject_id: 1, message: message)
    end

    before do
      finding(check: "C04", severity: "blocking", fingerprint: "fp-1", message: "Account 400 has a credit balance")
      finding(check: "C09", severity: "warning", fingerprint: "fp-2")
      finding(check: "C11", severity: "info", fingerprint: "fp-3")
    end

    it_behaves_like "an agent tool", permission: "reports.view"

    it "gives the anomalies of the last run with the count by severity" do
      result = run("get_consistency_findings", {})

      expect(result["data"].map { |f| f["check"] }).to eq(%w[C04 C09 C11])
      expect(result["data"].first).to include("severity" => "blocking", "message" => "Account 400 has a credit balance", "acknowledged" => false)
      expect(result["totals"]).to include("blocking" => "1", "warning" => "1", "info" => "1")
    end

    it "narrows by severity or by check" do
      expect(run("get_consistency_findings", { "severity" => "blocking" })["data"].map { |f| f["check"] }).to eq([ "C04" ])
      expect(run("get_consistency_findings", { "check_id" => "C09" })["data"].map { |f| f["check"] }).to eq([ "C09" ])
    end

    it "leaves out what an accountant acknowledged, unless asked" do
      Accounting::ConsistencyAcknowledgement.create!(fingerprint: "fp-1", comment: "Deposit received", user: user, acknowledged_at: Time.current)

      expect(run("get_consistency_findings", {})["data"].map { |f| f["check"] }).to eq(%w[C09 C11])
      shown = run("get_consistency_findings", { "include_acknowledged" => true })["data"]
      expect(shown.find { |f| f["check"] == "C04" }["acknowledged"]).to be true
    end

    it "says so when the checks have not run" do
      Accounting::ConsistencyFinding.delete_all
      Accounting::ConsistencyRun.delete_all

      expect(run("get_consistency_findings", {})["warnings"].join).to include("have not run yet")
    end

    it "only reads the findings of this entity" do
      ActsAsTenant.with_tenant(create(:entity)) do
        other = Accounting::ConsistencyRun.create!(started_at: 1.minute.from_now, trigger: "manual")
        Accounting::ConsistencyFinding.create!(run: other, check_id: "C01", severity: "blocking", fingerprint: "other", message: "Elsewhere")
      end

      expect(run("get_consistency_findings", {})["data"].map { |f| f["message"] }).not_to include("Elsewhere")
    end
  end

  describe Agent::Tools::GetAuditTrail do
    let(:tool) { described_class }
    let(:valid_args) { {} }

    before { create(:partner, name: "Audited SA") }

    it_behaves_like "an agent tool", permission: "audit.view", denied_role: :manager

    it "gives the events of the report, newest first, without the details of what changed" do
      logs = Accounting::AuditLogsQuery.new({}).call.limit(25)
      result = run("get_audit_trail", {})

      expect(result["data"].map { |l| l["ref"] }).to eq(logs.map { |l| "audit:#{l.id}" })
      expect(result["data"].first.keys).to contain_exactly("at", "action", "object_type", "object_id", "user", "reason", "ref").or include("at", "action", "ref")
      expect(result.to_json).not_to include("Audited SA")
    end

    it "narrows by kind of object and by action" do
      result = run("get_audit_trail", { "auditable_type" => "Accounting::Partner", "action" => "create" })

      expect(result["data"]).to all(include("object_type" => "Accounting::Partner", "action" => "create"))
      expect(result["data"]).not_to be_empty
    end

    it "pages, newest first" do
      first = run("get_audit_trail", { "limit" => 1 })

      expect(first["next_cursor"]).to be_present
      expect(run("get_audit_trail", { "limit" => 1, "cursor" => first["next_cursor"] })["data"].first["ref"]).not_to eq(first["data"].first["ref"])
    end
  end

  describe Agent::Tools::SearchDocuments do
    let(:tool) { described_class }
    let(:valid_args) { { "q" => "loyer" } }
    let!(:lease) { create(:document, name: "loyer-janvier.pdf", kind: :purchase_invoice) }
    let!(:other) { create(:document, name: "assurance.pdf") }

    it_behaves_like "an agent tool", permission: "documents.view"

    it "finds documents by the words of their name, with what they are" do
      result = run("search_documents", { "q" => "loyer" })

      expect(result["data"]).to eq([ { "name" => "loyer-janvier.pdf", "kind" => "purchase_invoice", "status" => "inbox", "origin" => "manual_upload", "added" => today.iso8601, "ref" => "doc:#{lease.id}" } ])
    end

    it "gives the same documents as the model's own search" do
      expect(run("search_documents", { "q" => "pdf" })["data"].map { |d| d["ref"] }).to match_array(Accounting::Document.search("pdf").map { |d| "doc:#{d.id}" })
    end

    it "never gives the content of a document" do
      expect(run("search_documents", { "q" => "loyer" }).to_json).not_to include("extracted", "sha256", "content")
    end

    it "refuses a total that is not a decimal" do
      expect(run("search_documents", { "q" => "loyer", "min_total" => "lots" })).to include("error" => "invalid_arguments")
    end
  end
end
