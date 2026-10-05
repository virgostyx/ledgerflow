require "rails_helper"

# F12b: the consolidation of a group, on a reference group whose books are kept in their own tenants. A rule that no accountant validated is not applied.
RSpec.describe Consolidation::Compute, :consolidation do
  let(:parents) { parent_and_subsidiary }
  let(:parent) { parents.first }
  let(:sub) { parents.last }
  let(:group) { make_group(parent, members: { sub => { stake: 80 } }) }
  let(:run) { new_run(group) }
  let(:date) { ConsolidationHelpers::DATE }

  def figures = run.reload.figures
  def amount(code) = BigDecimal(figures["figures"].fetch(code))
  def review = ActsAsTenant.with_tenant(parent) { Consolidation::Review.issues(run.reload) }

  describe "the cumulation, with no rule validated" do
    before { compute(run) }

    it "adds up the headings of the two companies, each read in its own books, and the consolidated balance sheet balances" do
      expect(figures["collection"]["members"].map { |m| [ m["name"], m["stake"] ] }).to eq([ [ "Parent SA", "100.0" ], [ "Sub SRL", "80.0" ] ])
      expect(figures["cumul"]).to include("54/58" => "133000.0", "29" => "20000.0", "40/41" => "1000.0", "10/11" => "130000.0", "42/48" => "1000.0", "17" => "20000.0", "70" => "6000.0", "61" => "3000.0")
      expect([ amount("20/58"), amount("10/49"), amount("9904") ]).to eq([ BigDecimal("154000"), BigDecimal("154000"), BigDecimal("3000") ])
      expect(figures["difference"]).to eq("0.0")
      expect(figures["balance_steps"].map { |s| s["difference"] }).to eq([ "0.0" ])
    end

    it "applies no rule: no entry, and what the rules would need is said to be unvalidated" do
      expect(figures["rules"].transform_values { |s| s["state"] }).to eq("intragroup_balances" => "not_validated", "intragroup_flows" => "not_validated", "minority_interests" => "not_validated",
                                                                         "equity_method" => "not_required", "translation" => "not_required")
      expect(ActsAsTenant.with_tenant(parent) { run.entries.count }).to eq(0)
      expect(amount("29")).to eq(20_000) # the loan is still there: nothing was eliminated
      expect(review.select { |i| i.severity == "blocking" }.map(&:message)).to include(a_string_matching(/Eliminate intragroup receivables and payables is needed.*no accountant's validation/),
                                                                                       a_string_matching(/Minority interests is needed/))
    end

    it "still compares what the two companies say of each other (a mechanism, not a rule), with the proposals of the application marked as such" do
      balances = figures["intragroup"]["balances"]
      expect(balances.map { |r| [ r["creditor"], r["debtor"], r["heading_creditor"], r["heading_debtor"], r["amount_creditor"], r["amount_debtor"], r["difference"] ] })
        .to match_array([ [ "Parent SA", "Sub SRL", "29", "17", "20000.0", "20000.0", "0.0" ], [ "Sub SRL", "Parent SA", "40/41", "42/48", "1000.0", "1000.0", "0.0" ] ])
      expect(figures["intragroup"]["flows"].map { |r| [ r["creditor"], r["amount_creditor"], r["amount_debtor"] ] }).to eq([ [ "Sub SRL", "1000.0", "1000.0" ] ])
      expect(figures["defaults_used"]).to match_array(%w[intragroup_balances intragroup_flows])
    end
  end

  describe "with the rules validated by an accountant" do
    before do
      %w[intragroup_balances intragroup_flows minority_interests].each { |key| validate_rule(group, key) }
      compute(run)
    end

    it "eliminates the receivables and payables, then the sales and purchases, and keeps the balance sheet balanced at every step (criteria 3 and 5)" do
      entries = ActsAsTenant.with_tenant(parent) { run.entries.includes(:lines).order(:id).map { |e| [ e.kind, e.rule_key, e.lines.map { |l| [ l.statement, l.code, l.side, l.amount ] } ] } }
      expect(entries).to match_array([
        [ "intragroup_balances", "intragroup_balances", [ [ "liabilities", "17", "debit", 20_000 ], [ "assets", "29", "credit", 20_000 ] ] ],
        [ "intragroup_balances", "intragroup_balances", [ [ "liabilities", "42/48", "debit", 1000 ], [ "assets", "40/41", "credit", 1000 ] ] ],
        [ "intragroup_flows", "intragroup_flows", [ [ "income", "70", "debit", 1000 ], [ "income", "61", "credit", 1000 ] ] ]
      ])
      expect([ amount("29"), amount("40/41"), amount("17"), amount("42/48"), amount("70"), amount("61") ]).to eq([ 0, 0, 0, 0, 5000, 2000 ].map { |v| BigDecimal(v) })
      expect([ amount("20/58"), amount("10/49"), amount("9904") ]).to eq([ BigDecimal("133000"), BigDecimal("133000"), BigDecimal("3000") ])
      expect(figures["balance_steps"].size).to eq(4)
      expect(figures["balance_steps"].map { |s| s["difference"] }.uniq).to eq([ "0.0" ])
    end

    it "gives the minority 20 % of the equity and of the result of the subsidiary held at 80 % (criterion 4)" do
      minority = figures["minority"]
      expect(minority["members"]).to eq([ { "member_id" => minority["members"].first["member_id"], "name" => "Sub SRL", "stake" => "80.0", "equity" => "5800.0", "result" => "-200.0" } ])
      expect(minority).to include("equity" => "5800.0", "result" => "-200.0", "group_equity" => "127200.0", "group_result" => "3200.0")
    end

    it "applies each rule with the parameters that were validated, not the application's proposal" do
      expect(figures["rules"]["intragroup_balances"]["validation"]).to include("by" => "Jane Doe", "title" => "Chartered accountant, Doe & Co", "parameters" => { "pairs" => [ %w[40/41 42/48], %w[29 17] ] })
      expect(figures["defaults_used"]).to eq([])
    end

    it "is worked out again from the beginning each time, and keeps the entries a person made" do
      ActsAsTenant.with_tenant(parent) do
        manual = run.entries.build(kind: "adjustment", comment: "A correction", created_by: nil)
        manual.lines.build(statement: "assets", code: "3", side: "debit", amount: 10)
        manual.lines.build(statement: "liabilities", code: "13", side: "credit", amount: 10)
        manual.save!
      end
      compute(run)
      compute(run)
      expect(ActsAsTenant.with_tenant(parent) { run.entries.pluck(:rule_key) }).to match_array([ nil, "intragroup_balances", "intragroup_balances", "intragroup_flows" ])
      expect(amount("3")).to eq(10)
      expect(figures["balance_steps"].map { |s| s["difference"] }.uniq).to eq([ "0.0" ])
    end
  end

  describe "an intragroup difference (criterion 6)" do
    let(:parents) { parent_and_subsidiary(payable_in_parent: "800.00") } # the parent records 800 of purchases and of payable where the subsidiary says 1 000
    before { %w[intragroup_balances intragroup_flows minority_interests].each { |key| validate_rule(group, key) } }

    it "is shown with its amount, and blocks the validation until an adjustment is recorded" do
      compute(run)
      row = figures["intragroup"]["balances"].find { |r| r["heading_creditor"] == "40/41" }
      expect([ row["amount_creditor"], row["amount_debtor"], row["difference"] ]).to eq([ "1000.0", "800.0", "200.0" ])
      expect(review.select { |i| i.severity == "blocking" }.map(&:message)).to include(a_string_matching(/Intragroup difference of 200\.00 between the receivable of Sub SRL \(1000\.0\) and payable of Parent SA \(800\.0\)/))
      expect { ActsAsTenant.with_tenant(parent) { Consolidation::Finalize.validate!(run.reload, nil) } }.to raise_error(Consolidation::Finalize::Refused, /Intragroup difference of 200\.00/)
      expect(run.reload).to be_draft
    end

    it "is let through once an adjustment entry for that pair explains it; a smaller one leaves the rest blocking" do
      compute(run)
      adjust = lambda do |kind, amount|
        ActsAsTenant.with_tenant(parent) do
          context = kind == "balances" ? { "heading_creditor" => "40/41", "heading_debtor" => "42/48" } : { "heading_creditor" => "70", "heading_debtor" => "61" }
          entry = run.entries.build(kind: "intercompany_adjustment", comment: "Invoice in transit", context: { "kind" => kind, "creditor_id" => sub.id, "debtor_id" => parent.id }.merge(context))
          statement, code, other = kind == "balances" ? [ "liabilities", "42/48", [ "assets", "40/41" ] ] : [ "income", "70", [ "income", "61" ] ]
          entry.lines.build(statement: statement, code: code, side: "debit", amount: amount)
          entry.lines.build(statement: other.first, code: other.last, side: "credit", amount: amount)
          entry.save!
        end
        compute(run)
      end
      adjust.call("balances", 50)
      expect(review.map(&:message)).to include(a_string_matching(/Intragroup difference of 150\.00 between the receivable/))
      adjust.call("balances", 150)
      adjust.call("flows", 200)
      expect(review.select { |i| i.severity == "blocking" }.map(&:message).grep(/Intragroup difference/)).to eq([])
      expect(ActsAsTenant.with_tenant(parent) { Consolidation::Finalize.validate!(run.reload, nil) }).to be_validated
    end
  end

  it "refuses an entry that does not balance, one with a single line, a heading that holds no accounts, and a dividend or a participation without its document" do
    compute(run)
    ActsAsTenant.with_tenant(parent) do
      entry = run.entries.build(kind: "adjustment", comment: "x")
      entry.lines.build(statement: "assets", code: "3", side: "debit", amount: 10)
      entry.lines.build(statement: "liabilities", code: "13", side: "credit", amount: 9)
      expect(entry).not_to be_valid
      expect(entry.errors.full_messages.to_sentence).to include("does not balance: debit 10.00, credit 9.00")

      single = run.entries.build(kind: "adjustment", comment: "x")
      single.lines.build(statement: "assets", code: "3", side: "debit", amount: 10)
      expect(single.tap(&:valid?).errors.full_messages.to_sentence).to include("at least two lines")

      total = run.entries.build(kind: "adjustment", comment: "x")
      total.lines.build(statement: "assets", code: "20/58", side: "debit", amount: 10)
      total.lines.build(statement: "liabilities", code: "13", side: "credit", amount: 10)
      expect(total).not_to be_valid

      dividend = run.entries.build(kind: "dividends", comment: "Dividend")
      dividend.lines.build(statement: "assets", code: "3", side: "debit", amount: 10)
      dividend.lines.build(statement: "liabilities", code: "13", side: "credit", amount: 10)
      expect(dividend.tap(&:valid?).errors.full_messages.to_sentence).to include("Document is required")
    end
  end

  describe "the members" do
    it "refuses a member with no percentage, with no fiscal year at the date, and a member whose statements do not balance" do
      group_without_stake = ActsAsTenant.with_tenant(parent) { Consolidation::Group.create!(name: "G", currency: "EUR") }
      add_member(group_without_stake, parent, stake: 100)
      ActsAsTenant.with_tenant(parent) { group_without_stake.members.create!(member_entity: sub) } # no stake
      compute(new_run(group_without_stake))
      run2 = Consolidation::Run.unscoped.where(consolidation_group_id: group_without_stake.id).first
      expect(run2.figures["collection"]["errors"]).to include("Sub SRL: no percentage held at #{date}.")

      compute(new_run(group, date: Date.new(2030, 12, 31)))
      expect(Consolidation::Run.unscoped.where(consolidation_group_id: group.id).last.figures["collection"]["errors"]).to include(a_string_matching(/Parent SA: no fiscal year contains 2030-12-31/))
    end

    it "marks an open fiscal year or an end on another day as provisional, with a warning, and takes the situation at the reporting date" do
      compute(run)
      expect(run.reload.provisional).to be(true)
      expect(figures["collection"]["warnings"]).to include("Parent SA: fiscal year 2026 is not closed: provisional.")

      ActsAsTenant.with_tenant(sub) { Accounting::FiscalYear.first.update!(status: :closed, closed_at: Time.current) }
      ActsAsTenant.with_tenant(parent) { Accounting::FiscalYear.first.update!(status: :closed, closed_at: Time.current) }
      middle = new_run(group, date: Date.new(2026, 6, 30))
      compute(middle)
      expect(middle.reload.figures["collection"]["warnings"]).to include("Parent SA: its fiscal year ends 2026-12-31, the statements are its situation at 2026-06-30.")
      expect(BigDecimal(middle.figures["cumul"]["54/58"])).to eq(BigDecimal("130000")) # on 2026-06-30: 100 000 − 20 000 in the parent, 30 000 + 20 000 in the subsidiary; the rest of the year is later
    end

    it "leaves out a member that is not in the scope at the date, and refuses a change of scope inside the period" do
      ActsAsTenant.with_tenant(parent) { group.members.find_by(member_entity: sub).update!(joined_on: Date.new(2026, 7, 1)) }
      compute(run)
      expect(figures["collection"]["facts"]["scope_change"]).to be(true)
      expect(review.select { |i| i.severity == "blocking" }.map(&:message)).to include(a_string_matching(/joined or left during the period/))

      ActsAsTenant.with_tenant(parent) { group.members.find_by(member_entity: sub).update!(joined_on: nil, left_on: Date.new(2026, 6, 1)) }
      compute(run)
      expect(figures["collection"]["members"].map { |m| m["name"] }).to eq([ "Parent SA" ])
      expect(figures["collection"]["warnings"]).to include("Sub SRL is not in the scope at #{date}: left out.")
    end

    it "keeps the history of the percentage held, by date of effect" do
      member = ActsAsTenant.with_tenant(parent) { group.members.find_by(member_entity: sub) }
      member.stakes.create!(percentage: 60, effective_on: Date.new(2026, 7, 1))
      expect([ member.stake_on(Date.new(2026, 6, 30)), member.stake_on(Date.new(2026, 7, 1)), member.stake_on(Date.new(2019, 1, 1)) ]).to eq([ BigDecimal("80"), BigDecimal("60"), nil ])
      expect(member.stakes.build(percentage: 50, effective_on: Date.new(2026, 7, 1))).not_to be_valid
      expect(member.stakes.build(percentage: 120, effective_on: Date.new(2027, 1, 1))).not_to be_valid
    end
  end

  describe "an accountant's validation of a rule" do
    it "needs who, in what capacity, when, where it is written and the parameters; a date in the future is refused; one in force at a time" do
      expect { validate_rule(group, "minority_interests", validated_by_name: "") }.to raise_error(ActiveRecord::RecordInvalid)
      expect { validate_rule(group, "minority_interests", validated_on: Date.current + 1) }.to raise_error(ActiveRecord::RecordInvalid, /future/)
      expect { validate_rule(group, "minority_interests", parameters: { "equity_heading" => "10/15" }) }.to raise_error(ActiveRecord::RecordInvalid, /lack: result_heading/)
      expect { validate_rule(group, "made_up_rule") }.to raise_error(ActiveRecord::RecordInvalid)

      first = validate_rule(group, "minority_interests")
      expect { validate_rule(group, "minority_interests") }.to raise_error(ActiveRecord::RecordNotUnique)
      first.revoke!
      expect(validate_rule(group, "minority_interests")).to be_persisted
      expect(ActsAsTenant.with_tenant(parent) { group.reload.validation_for("minority_interests") }.id).not_to eq(first.id)
    end

    it "stops applying a rule once its validation is revoked" do
      validation = validate_rule(group, "minority_interests")
      compute(run)
      expect(figures["minority"]["applied"]).to be(true)
      validation.revoke!
      compute(run)
      expect(figures["minority"]["applied"]).to be(false)
      expect(figures["rules"]["minority_interests"]["state"]).to eq("not_validated")
    end
  end
end
