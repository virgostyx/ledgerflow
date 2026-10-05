# F12b: works a run out, from the beginning, each time it is asked (a draft is recomputed, never patched): collection of every member in its own tenant,
# translation of a foreign member (rule validated), the intragroup comparison, the entries that the VALIDATED rules propose (recreated each time; the entries a person
# made are kept), the cumulation and the entries applied one by one with the balance of the consolidated balance sheet checked at each step, the minority interests and
# the equity method (rules validated), then the review that says what blocks. Nothing is written in the books of any company, and a rule with no validation is not applied.
class Consolidation::Compute
  AUTO = { "intragroup_balances" => "balances", "intragroup_flows" => "flows" }.freeze

  def self.call(run) = new(run).call

  # What the books said when the run was worked out: if it is not the same now, the run is stale (a validation or a freezing refuses it).
  def self.source_digest(collection) = Accounting::ClosingSnapshot.fingerprint(collection["members"].map { |m| m.slice("entity_id", "fiscal_year", "figures", "own") })

  def initialize(run)
    @run = run
    @group = run.group
    @date = run.reporting_date
  end

  def call
    raise ArgumentError, "a #{@run.status} run is not recomputed" unless @run.draft?

    collection = Consolidation::Collect.call(@group, @date)
    digest = Consolidation::Compute.source_digest(collection)
    members = translate(collection)
    full = members.select { |m| m["method"] == "full" }
    rows = { "balances" => intragroup("balances", full), "flows" => intragroup("flows", full) }
    rules = rules_state(collection, rows)
    ApplicationRecord.transaction do
      @run.entries.where.not(rule_key: nil).includes(:lines).destroy_all
      propose_eliminations(rows, rules)
      @run.entries.reload
      @run.update!(figures: assemble(collection, members, full, rows, rules).merge("source_digest" => digest), provisional: collection["provisional"])
    end
    @run
  end

  private

  def validation(key) = @group.validation_for(key)

  def params(key) = validation(key)&.parameters || Consolidation::Rules.fetch(key)[:parameters]

  # Foreign members, translated when the rule is validated, and left as collected (and refused at review) when it is not.
  def translate(collection)
    collection["members"].map do |member|
      next member if member["currency"] == @group.currency || validation("translation").nil?

      Consolidation::Translate.call(member, parameters: params("translation"), group_currency: @group.currency, date: @date)
    rescue Consolidation::Translate::Failed, Fx::MissingRate => e
      collection["errors"] << "#{member['name']}: translation failed: #{e.message}"
      member
    end
  end

  def intragroup(kind, full)
    pairs = params("intragroup_#{kind}")["pairs"]
    Consolidation::Intragroup.rows(full, @date, kind: kind, pairs: pairs)
  end

  def rules_state(collection, rows)
    facts = collection["facts"]
    required = { "intragroup_balances" => rows["balances"].any?, "intragroup_flows" => rows["flows"].any?, "minority_interests" => facts["minority"],
                 "equity_method" => facts["equity"], "translation" => facts["foreign"] }
    Consolidation::Rules.keys.index_with do |key|
      v = validation(key)
      { "required" => required.fetch(key), "state" => v ? "applied" : (required.fetch(key) ? "not_validated" : "not_required"),
        "validation" => v && { "id" => v.id, "by" => v.validated_by_name, "title" => v.validated_by_title, "on" => v.validated_on.iso8601, "reference" => v.reference, "parameters" => v.parameters } }
    end
  end

  def propose_eliminations(rows, rules)
    AUTO.each do |rule, kind|
      next unless rules.dig(rule, "state") == "applied"

      rows[kind].select { |row| row.matched.positive? }.each do |row|
        statements = Consolidation::Intragroup.statements_of(kind)
        debit_line, credit_line = kind == "balances" ? [ [ statements.last, row.heading_debtor ], [ statements.first, row.heading_creditor ] ] : [ [ "income", row.heading_creditor ], [ "income", row.heading_debtor ] ]
        entry = @run.entries.build(kind: rule, rule_key: rule, comment: "#{kind == 'balances' ? 'Receivable of' : 'Sales of'} #{row.creditor} on #{row.debtor}, headings #{row.heading_creditor} / #{row.heading_debtor}",
                                   context: context_of(row), created_by: nil)
        entry.lines.build(statement: debit_line.first, code: debit_line.last, side: "debit", amount: row.matched)
        entry.lines.build(statement: credit_line.first, code: credit_line.last, side: "credit", amount: row.matched)
        entry.save!
      end
    end
  end

  def context_of(row) = { "kind" => row.kind, "creditor_id" => row.creditor_id, "debtor_id" => row.debtor_id, "heading_creditor" => row.heading_creditor, "heading_debtor" => row.heading_debtor }

  def assemble(collection, members, full, rows, rules)
    own = Hash.new(BigDecimal("0"))
    full.each { |m| m["own"].each { |code, amount| own[code] += BigDecimal(amount) } }
    steps = [ { "label" => "Cumulated companies", "difference" => Consolidation::Statements.difference(Consolidation::Statements.compute(own: own)).to_s("F") } ]
    deltas = Hash.new(BigDecimal("0"))
    @run.entries.includes(:lines).order(:id).each do |entry|
      entry.deltas.each { |code, delta| deltas[code] += delta }
      steps << { "label" => "#{entry.kind}: #{entry.comment}", "entry_id" => entry.id, "difference" => Consolidation::Statements.difference(Consolidation::Statements.compute(own: own, deltas: deltas)).to_s("F") }
    end
    figures = Consolidation::Statements.compute(own: own, deltas: deltas)
    { "collection" => collection.merge("members" => members), "rules" => rules, "adjustments" => adjustments, "intragroup" => rows.transform_values { |list| list.map(&:to_h) },
      "defaults_used" => AUTO.keys.reject { |k| validation(k) }, "cumul" => own.transform_values { |v| v.to_s("F") }, "figures" => figures.transform_values { |v| v.to_s("F") },
      "difference" => Consolidation::Statements.difference(figures).to_s("F"), "balance_steps" => steps, "minority" => minority(members, rules, figures),
      "equity_method" => equity_method(members, rules) }
  end

  # The adjustments recorded for each pair of intragroup headings: what explains a difference between what two companies say.
  def adjustments
    @run.entries.where(kind: "intercompany_adjustment").includes(:lines).map { |e| { "context" => e.context, "total" => e.total.to_s("F") } }
  end

  # Minority interests (rule validated): the share of the others in the equity and the result of each fully consolidated member held for less than 100 %.
  def minority(members, rules, figures)
    return { "applied" => false, "members" => [], "equity" => "0.0", "result" => "0.0" } unless rules.dig("minority_interests", "state") == "applied"

    parameters = params("minority_interests")
    list = members.select { |m| m["method"] == "full" && !m["parent"] && BigDecimal(m["stake"] || "100") < 100 }.map do |m|
      share = (BigDecimal("100") - BigDecimal(m["stake"])) / 100
      { "member_id" => m["member_id"], "name" => m["name"], "stake" => m["stake"], "equity" => (share * BigDecimal(m["figures"].fetch(parameters["equity_heading"]))).round(2).to_s("F"),
        "result" => (share * BigDecimal(m["figures"].fetch(parameters["result_heading"]))).round(2).to_s("F") }
    end
    equity, result = list.sum(BigDecimal("0")) { |x| BigDecimal(x["equity"]) }, list.sum(BigDecimal("0")) { |x| BigDecimal(x["result"]) }
    { "applied" => true, "members" => list, "equity" => equity.to_s("F"), "result" => result.to_s("F"),
      "group_equity" => (figures.fetch(parameters["equity_heading"]) - equity).to_s("F"), "group_result" => (figures.fetch(parameters["result_heading"]) - result).to_s("F") }
  end

  # The share of the group in the equity and the result of each associate (rule validated): the figures the entry of the equity method is prepared from.
  def equity_method(members, rules)
    return [] unless rules.dig("equity_method", "state") == "applied"

    parameters = params("equity_method")
    members.select { |m| m["method"] == "equity" }.map do |m|
      share = BigDecimal(m["stake"]) / 100
      { "member_id" => m["member_id"], "name" => m["name"], "stake" => m["stake"], "equity" => (share * BigDecimal(m["figures"].fetch(parameters["equity_heading"]))).round(2).to_s("F"),
        "result" => (share * BigDecimal(m["figures"].fetch(parameters["result_heading"]))).round(2).to_s("F") }
    end
  end
end
