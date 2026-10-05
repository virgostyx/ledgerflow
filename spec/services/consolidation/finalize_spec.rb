require "rails_helper"

# F12b: access to every member (criterion 7), the frozen run (criterion 8), the queries (criterion 2), the foreign member and the equity method.
RSpec.describe "Consolidation controls", :consolidation do
  let(:parents) { parent_and_subsidiary }
  let(:parent) { parents.first }
  let(:sub) { parents.last }
  let(:group) { make_group(parent, members: { sub => { stake: 80 } }) }
  let(:owner) { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: parent) } }

  before { %w[intragroup_balances intragroup_flows minority_interests].each { |key| validate_rule(group, key) } }

  def validated_run(**options)
    run = new_run(group, **options)
    ActsAsTenant.with_tenant(parent) { Consolidation::Finalize.validate!(compute(run), owner) }
  end

  def frozen_run(**options)
    ActsAsTenant.with_tenant(parent) { Consolidation::Finalize.freeze!(validated_run(**options), owner) }
  end

  describe "access to every member (criterion 7)" do
    it "needs a current membership in the parent and in each member, and the feature on in each" do
      stranger = create(:user)
      create(:user_entity, :accountant, user: stranger, entity: parent)
      expect(Consolidation::Access.missing(stranger, group)).to eq(1)
      expect(Consolidation::Access.all_members?(stranger, group)).to be(false)

      create(:user_entity, :manager, user: stranger, entity: sub)
      expect(Consolidation::Access.all_members?(stranger, group)).to be(true)

      UserEntity.find_by(user: stranger, entity: sub).update_columns(valid_until: 1.day.ago.to_date)
      expect(Consolidation::Access.missing(stranger, group)).to eq(1) # an access that ended is no access

      UserEntity.find_by(user: stranger, entity: sub).update_columns(valid_until: nil)
      sub.update!(features: { "f12" => false })
      expect(Consolidation::Access.missing(stranger, group)).to eq(1) # a member that did not turn the feature on
    end
  end

  describe "a frozen run (criterion 8)" do
    it "is written once, with its SHA-256, and reads back the same" do
      run = frozen_run
      expect(run).to be_frozen
      expect(run.snapshot_sha256).to match(/\A\h{64}\z/)
      reread = Consolidation::Run.unscoped.find(run.id)
      expect(reread.intact?).to be(true)
      expect(reread.snapshot_sha256).to eq(run.snapshot_sha256)
      expect(reread.snapshot["statements"]["assets"].find { |r| r["code"] == "20/58" }["amount"]).to eq("133000.0")
      expect(reread.snapshot).to include("provisional" => true)
      expect(reread.snapshot["rules"]["minority_interests"]["validation"]).to include("by" => "Jane Doe")
      expect(reread.snapshot["members"].find { |m| m["name"] == "Sub SRL" }["stakes"]).to eq([ { "on" => "2020-01-01", "percentage" => "80.0" } ])
      expect(reread.figures).to eq({})
    end

    it "never changes: not its content, not its status, not its entries, and it is not deleted" do
      run = frozen_run
      expect(run.update(snapshot: { "tampered" => true })).to be(false)
      expect(run.errors.full_messages.to_sentence).to include("frozen run never changes")
      expect(Consolidation::Run.unscoped.find(run.id).intact?).to be(true)
      expect { run.destroy }.not_to change(Consolidation::Run.unscoped, :count)

      entry = ActsAsTenant.with_tenant(parent) { run.entries.build(kind: "adjustment", comment: "late") }
      entry.lines.build(statement: "assets", code: "3", side: "debit", amount: 1)
      entry.lines.build(statement: "liabilities", code: "13", side: "credit", amount: 1)
      expect(entry).not_to be_valid
      expect(entry.errors.full_messages.to_sentence).to include("run is frozen")

      Consolidation::Run.unscoped.where(id: run.id).update_all(snapshot: run.snapshot.merge("tampered" => true)) # a change made behind the application's back
      expect(Consolidation::Run.unscoped.find(run.id).intact?).to be(false)
    end

    it "does not compute, validate or freeze again, and refuses to freeze what was not validated" do
      run = frozen_run
      expect { compute(run) }.to raise_error(ArgumentError, /frozen run is not recomputed/)
      expect { Consolidation::Finalize.validate!(run, owner) }.to raise_error(Consolidation::Finalize::Refused, /only a draft/)
      expect { Consolidation::Finalize.freeze!(new_run(group), owner) }.to raise_error(Consolidation::Finalize::Refused, /only a validated run is frozen/)
    end

    it "refuses to freeze when a member's books changed since the validation" do
      run = validated_run
      book(sub, ConsolidationHelpers::DATE - 10, [ "550000", 500, 0 ], [ "700000", 0, 500 ])
      expect { ActsAsTenant.with_tenant(parent) { Consolidation::Finalize.freeze!(run, owner) } }.to raise_error(Consolidation::Finalize::Refused, /books of a member changed/)
      expect(run.reload).to be_validated
    end

    it "shows the differences with the run it replaces, and the first run has none" do
      first = frozen_run
      expect(ActsAsTenant.with_tenant(parent) { Consolidation::Diff.call(first) }).to be_nil

      book(sub, ConsolidationHelpers::DATE - 10, [ "550000", 500, 0 ], [ "700000", 0, 500 ])
      second = frozen_run
      expect(second.previous_run).to eq(first)
      diff = Consolidation::Diff.call(second)
      expect(diff["headings"].map { |h| [ h["code"], h["delta"] ] }).to include([ "54/58", "500.0" ], [ "70", "500.0" ], [ "9904", "500.0" ], [ "20/58", "500.0" ])
      expect(diff).to include("previous_run_id" => first.id, "members_added" => [], "members_removed" => [], "entries" => { "previous" => 3, "current" => 3 })
      expect(first.reload.intact?).to be(true) # the first one is as it was
    end
  end

  it "reads the books of each company inside its own tenant: no query on the books goes without its entity (criterion 2)" do
    run = new_run(group)
    queries = []
    binds = []
    callback = ->(*, payload) { (queries << payload[:sql]) && (binds << payload[:type_casted_binds].to_a.flatten) unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { compute(run) }

    book_queries = queries.select { |sql| sql.match?(/FROM "accounting_(journal_entries|journal_entry_lines|accounts|partners|fiscal_years)"/) }
    expect(book_queries.size).to be > 10
    expect(book_queries.reject { |sql| sql.include?("entity_id") }).to eq([])
    expect(book_queries.grep(/entity_id" IN|entity_id\s*=\s*\d+ OR/)).to eq([]) # never "this company or that one"
    scoped = queries.each_index.select { |i| queries[i].match?(/FROM "accounting_(journal_entries|journal_entry_lines|accounts|partners|fiscal_years)"/) }.map do |i|
      queries[i].scan(/"entity_id" = \$(\d+)/).flatten.map { |n| binds[i][n.to_i - 1] }.uniq # the company each condition on entity_id names
    end
    expect(scoped.map(&:size).uniq).to eq([ 1 ]) # one company at a time, in every query on the books
    expect(scoped.flatten.uniq).to match_array([ parent.id, sub.id ])
  end

  describe "a member that keeps its accounts in another currency, and an associate (four companies)" do
    let(:foreign) { company("Foreign Inc") }
    let(:associate) { company("Associate SA") }
    let(:group) { make_group(parent, members: { sub => { stake: 80 }, foreign => { stake: 100, currency: "USD" }, associate => { stake: 30, method: "equity" } }) }

    before do
      book(foreign, ConsolidationHelpers::DATE - 300, [ "550000", 22_000, 0 ], [ "100000", 0, 22_000 ])
      book(foreign, ConsolidationHelpers::DATE - 100, [ "550000", 2_400, 0 ], [ "700000", 0, 2_400 ])
      book(foreign, ConsolidationHelpers::DATE - 90, [ "610000", 1_200, 0 ], [ "550000", 0, 1_200 ])
      book(associate, ConsolidationHelpers::DATE - 300, [ "550000", 10_000, 0 ], [ "100000", 0, 10_000 ])
      book(associate, ConsolidationHelpers::DATE - 100, [ "550000", 3_000, 0 ], [ "700000", 0, 3_000 ])
      ActsAsTenant.with_tenant(foreign) do
        Accounting::ExchangeRate.create!(currency: "USD", rate_date: ConsolidationHelpers::DATE, rate: "1.10", rate_type: :closing, source: "manual", reason: "test")
        (1..12).each { |m| Accounting::ExchangeRate.create!(currency: "USD", rate_date: Date.new(2026, m, 1), rate: "1.20", rate_type: :monthly_average, source: "manual", reason: "test") }
      end
    end

    it "does not translate the foreign member and says so, until the rule is validated; the associate is not cumulated line by line" do
      run = new_run(group)
      compute(run)
      expect(run.reload.figures["rules"]["translation"]["state"]).to eq("not_validated")
      expect(run.figures["rules"]["equity_method"]["state"]).to eq("not_validated")
      expect(ActsAsTenant.with_tenant(parent) { Consolidation::Review.blocking(run).map(&:message) }).to include(a_string_matching(/Translation of a member.*no accountant's validation/),
                                                                                                                  a_string_matching(/Simple equity method is needed/))
      expect(BigDecimal(run.figures["cumul"]["54/58"])).to eq(BigDecimal("156200")) # 133 000 + 23 200 raw, as collected: NOT converted (and refused at review)
    end

    it "translates the balance sheet at the closing rate, the income at the mean of the monthly rates, and puts the difference in equity" do
      validate_rule(group, "translation")
      validate_rule(group, "equity_method")
      run = new_run(group)
      compute(run)
      figures = run.reload.figures
      translated = figures["collection"]["members"].find { |m| m["name"] == "Foreign Inc" }
      expect(translated["translation"]).to eq("closing_rate" => "1.1", "average_rate" => "1.2", "difference" => "90.91", "difference_heading" => "14")
      expect(translated["figures"]).to include("54/58" => "21090.91", "10/11" => "20000.0", "70" => "2000.0", "61" => "1000.0", "9904" => "1000.0")
      expect(translated["figures"]["14"]).to eq("1090.91") # the difference 90.91 and the result 1 000
      expect(figures["difference"]).to eq("0.0")
      expect(figures["rules"]["translation"]["state"]).to eq("applied")
    end

    it "gives the share of the group in an associate (equity method), for the entry a person prepares from it, and keeps it out of the lines" do
      validate_rule(group, "equity_method")
      run = new_run(group)
      compute(run)
      figures = run.reload.figures
      expect(figures["equity_method"].map { |e| e.slice("name", "stake", "equity", "result") }).to eq([ { "name" => "Associate SA", "stake" => "30.0", "equity" => "3900.0", "result" => "900.0" } ])
      expect(BigDecimal(figures["cumul"]["54/58"])).to eq(BigDecimal("156200")) # the associate's 13 000 of cash is not in it
    end

    it "refuses a translation with a missing rate, naming the currency and the month, and never replaces it with another" do
      validate_rule(group, "translation")
      ActsAsTenant.with_tenant(foreign) { Accounting::ExchangeRate.monthly_average.where(rate_date: Date.new(2026, 5, 1)).delete_all }
      run = new_run(group)
      compute(run)
      expect(run.reload.figures["collection"]["errors"]).to include(a_string_matching(/Foreign Inc: translation failed: No monthly average exchange rate for USD on 01\/05\/2026/))
    end

    it "refuses a translation rule with parameters that are not supported, and a heading of equity that does not exist" do
      validate_rule(group, "translation", parameters: { "balance_rate_type" => "daily", "income_rate_type" => "monthly_average", "difference_heading" => "14" })
      run = new_run(group)
      compute(run)
      expect(run.reload.figures["collection"]["errors"]).to include(a_string_matching(/balance_rate_type "daily" is not supported/))
    end
  end
end
