require "rails_helper"

# A08: the two tools that explain an anomaly or a change: get_finding_context and get_variation.
RSpec.describe "The diagnosis tools of the agent" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: user, entity: entity) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en, today: fiscal_year.start_date + 90) }
  let(:registry) { Agent::ToolRegistry.new([ Agent::Tools::GetFindingContext, Agent::Tools::GetVariation, Agent::Tools::GetConsistencyFindings ]) }
  let(:journal) { create(:journal, :purchase) }
  let(:supplier) { create(:partner, :supplier, name: "Fournisseur Dupont SA", vat_number: nil) }

  def run(name, args, ctx = context) = registry.execute(name, args, ctx)

  def post(date, amount, debit:, credit:, partner: nil)
    entry = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: date, status: :draft, reference: nil, description: "Movement")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: debit, debit: BigDecimal(amount), credit: 0, label: "Movement", partner: (partner if debit.code.start_with?("44")))
    create(:journal_entry_line, journal_entry: entry, account: credit, debit: 0, credit: BigDecimal(amount), label: "Movement", partner: (partner if credit.code.start_with?("44")))
    Accounting::PostJournalEntry.call!(entry: entry)
    entry
  end

  describe Agent::Tools::GetFindingContext do
    let(:tool) { described_class }
    let(:valid_args) { { "finding_id" => finding.id } }
    # a refund on a supplier with no invoice: the supplier account has a debit balance (check C04)
    let!(:refund) { post(fiscal_year.start_date + 10, "250.00", debit: account_440, credit: account_604, partner: supplier) }
    let!(:run_record) { Accounting::Consistency::Runner.call(trigger: "spec", fiscal_year: fiscal_year) }
    let(:finding) { Accounting::ConsistencyFinding.find_by!(check_id: "C04") }

    it_behaves_like "an agent tool", permission: "reports.view"

    it "gives the anomaly with its figures, its subject, and the protocol that applies with its validation status" do
      row = run("get_finding_context", valid_args)["data"].first

      expect(row["finding"]).to include("check" => "C04", "severity" => "warning", "check_title" => "Account with an inverted balance", "ref" => "R19:#{finding.id}")
      expect(row["finding"]["data"]).to include("net" => "250.00")
      expect(row["subject"]).to include("type" => "Account", "ref" => "account:#{finding.subject_id}")
      expect(row["protocol"]).to include("id" => "C04", "validated" => false)
      expect(row["protocol"]["fix_steps"].first).to include("ref" => "screen:lettering")
      expect(row["protocol"]["checks"].map { |check| check["tool"] }).to include("get_aged_balance", "list_unreconciled", "get_ledger")
    end

    it "says that the protocol is not validated, so that the certainty is lowered" do
      expect(run("get_finding_context", valid_args)["warnings"].join).to include("not been validated by an accountant")
    end

    it "says whether the anomaly is still there, and that it is gone once the books are corrected" do
      expect(run("get_finding_context", valid_args)["data"].first["still_present"]).to be true

      post(fiscal_year.start_date + 20, "250.00", debit: account_604, credit: account_440, partner: supplier)
      result = run("get_finding_context", valid_args)

      expect(result["data"].first["still_present"]).to be false
      expect(result["warnings"].join).to include("no longer found")
    end

    it "says that the books moved since the check ran" do
      post(fiscal_year.start_date + 20, "1.00", debit: account_604, credit: account_440, partner: supplier)

      expect(run("get_finding_context", valid_args)["warnings"].join).to include("books changed since the check ran")
    end

    it "recalls that a person acknowledged it, and why" do
      Accounting::ConsistencyAcknowledgement.create!(fingerprint: finding.fingerprint, comment: "Advance paid to the supplier", user: user, acknowledged_at: Time.current)

      row = run("get_finding_context", valid_args)["data"].first

      expect(row["acknowledgement"]).to include("comment" => "Advance paid to the supplier")
    end

    it "shows the audit events of the subject to a person who may see the audit trail, and says what it could not show to one who may not" do
      expect(run("get_finding_context", valid_args)["data"].first).not_to have_key("audit_events") if Permissions.allowed?(:accountant, "audit.view") == false
      auditor = create(:user)
      create(:user_entity, :admin, user: auditor, entity: entity)
      admin_context = Agent::Context.build(user: auditor, entity: entity, locale: :en, today: context.today)

      expect(run("get_finding_context", valid_args, admin_context)["data"].first["audit_events"]).to be_a(Array)
    end

    it "answers not found for an anomaly that does not exist, and never gives one of another entity" do
      expect(run("get_finding_context", { "finding_id" => 0 + 999_999 })).to include("error" => "not_found")
      other = create(:entity)
      foreign = ActsAsTenant.with_tenant(other) { Accounting::ConsistencyRun.create!(trigger: "spec", started_at: Time.current).findings.create!(entity: other, check_id: "C04", severity: "warning", fingerprint: "x", message: "FOREIGN") }

      expect(run("get_finding_context", { "finding_id" => foreign.id })).to include("error" => "not_found")
    end

    it "says there is no protocol for a check that has none" do
      finding.update_columns(check_id: "C99")

      result = run("get_finding_context", valid_args)

      expect(result["data"].first).not_to have_key("protocol")
      expect(result["warnings"].join).to include("No diagnostic protocol")
    end

    it "points an invariant anomaly to the protocol of the invariant" do
      finding.update_columns(check_id: "C11", data: { "invariant" => "I7", "residual" => "12.5" })

      row = run("get_finding_context", valid_args)["data"].first

      expect(row["protocol"]["id"]).to eq("I7")
      expect(row["finding"]["data"]["residual"]).to eq("12.50")
    end
  end

  describe Agent::Tools::GetVariation do
    let(:tool) { described_class }
    let(:valid_args) { { "account_prefix" => "604", "first_from" => (fiscal_year.start_date).iso8601, "first_to" => (fiscal_year.start_date + 29).iso8601, "second_from" => (fiscal_year.start_date + 30).iso8601, "second_to" => (fiscal_year.start_date + 59).iso8601 } }

    before do
      post(fiscal_year.start_date + 1, "100.00", debit: account_604, credit: account_440, partner: supplier)
      post(fiscal_year.start_date + 31, "100.00", debit: account_604, credit: account_440, partner: supplier)
      post(fiscal_year.start_date + 35, "900.00", debit: account_604, credit: account_440, partner: supplier)
    end

    it_behaves_like "an agent tool", permission: "reports.view"

    it "gives the change, the share of the biggest contributor, and its largest line" do
      result = run("get_variation", valid_args)

      expect(result["totals"]).to include("first_period" => "100.00", "second_period" => "1000.00", "change" => "900.00")
      expect(result["data"].first).to include("account_code" => "604000", "change" => "900.00", "largest_line_second_period" => "900.00", "share_of_total_change_percent" => "100.00", "largest_line_percent_of_change" => "100.00")
    end

    it "marks a partner that has nothing in the first period as new" do
      result = run("get_variation", valid_args.merge("account_prefix" => "440", "group_by" => "partner"))

      expect(result["data"].first).to include("partner" => "Fournisseur Dupont SA", "ref" => "partner:#{supplier.id}")
    end

    it "warns about periods of different lengths and about overlapping periods" do
      result = run("get_variation", valid_args.merge("second_to" => (fiscal_year.start_date + 80).iso8601))
      overlapping = run("get_variation", valid_args.merge("second_from" => (fiscal_year.start_date + 10).iso8601))

      expect(result["warnings"].join).to include("do not have the same length")
      expect(overlapping["warnings"].join).to include("overlap")
    end

    it "refuses a period that ends before it starts" do
      expect(run("get_variation", valid_args.merge("first_to" => (fiscal_year.start_date - 5).iso8601))).to include("error" => "invalid_arguments")
    end

    it "says that a result lists only the biggest contributors" do
      post(fiscal_year.start_date + 40, "5.00", debit: account_651200, credit: account_440, partner: supplier)

      result = run("get_variation", valid_args.merge("account_prefix" => "6", "limit" => 1))

      expect(result["truncated"]).to be true
      expect(result["warnings"].join).to include("biggest contributors")
    end
  end

  describe "the prioritization of the anomalies" do
    before do
      post(fiscal_year.start_date + 10, "250.00", debit: account_440, credit: account_604, partner: supplier)
      Accounting::Consistency::Runner.call(trigger: "spec", fiscal_year: fiscal_year)
    end

    it "ranks the open anomalies by severity first, with the reasons, at most twenty" do
      result = run("get_consistency_findings", { "prioritize" => true })

      expect(result["data"].first).to include("priority_rank" => 1, "ref" => a_string_starting_with("R19:"))
      expect(result["data"].first["priority_reasons"]).to include("severity")
      expect(result["row_count"]).to be <= 20
    end
  end
end
