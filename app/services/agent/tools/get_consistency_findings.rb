# What the consistency checks found at their last run (A02, R19): the anomalies to fix, by severity, with the ones already acknowledged left out unless asked.
class Agent::Tools::GetConsistencyFindings < Agent::Tools::Base
  tool_name "get_consistency_findings"
  description "Returns the anomalies found by the consistency checks of the books at their last run: for each, the check, the severity (blocking, warning, info), what it is about and a message. " \
              "Anomalies an accountant already acknowledged are left out unless asked for. Use it for what to fix before a closing or a filing, or to explain an anomaly the person mentions. " \
              "With prioritize, it ranks them for 'what should I fix first?'. To explain one anomaly, use get_finding_context. Do not use it to correct anything (the agent cannot) or to read amounts: use the report tools."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false,
               properties: { severity: { type: "string", enum: Accounting::ConsistencyFinding::SEVERITIES, description: "Only this severity." },
                             check_id: { type: "string", pattern: "^C\\d{2}$", maxLength: 3, description: "Only this check, e.g. C04." },
                             include_acknowledged: { type: "boolean", description: "Also the anomalies already acknowledged (default false)." },
                             prioritize: { type: "boolean", description: "Rank the open anomalies in the order to fix them (severity, blocking effect on a closing or a VAT filing, amount involved, age), at most 20, with the reasons of each rank." } }.merge(paging(max: 50))
  classify "data.*.message" => :free_text

  def call(args, _context)
    run = Accounting::ConsistencyRun.latest_first.first
    return Agent::ToolResult.build(data: [], filters_applied: args.slice("severity", "check_id"), warnings: [ "The consistency checks have not run yet for this entity." ]) unless run

    findings = run.findings.order(:id)
    findings = findings.where(severity: args["severity"]) if args["severity"]
    findings = findings.where(check_id: args["check_id"]) if args["check_id"]
    acknowledged = Accounting::ConsistencyAcknowledgement.where(fingerprint: findings.select(:fingerprint)).pluck(:fingerprint).to_set
    findings = findings.where.not(fingerprint: acknowledged.to_a) unless args["include_acknowledged"]
    return prioritized(findings, acknowledged, run, args) if args["prioritize"]

    rows, next_cursor = page(findings, args, default: 25, max: 50)
    Agent::ToolResult.build(
      data: rows.map { |finding| row_for(finding, acknowledged) },
      totals: findings.reorder(nil).group(:severity).count.transform_values(&:to_s).merge("ref" => Agent::Refs.build("R19", run.id)),
      as_of: run.started_at.to_date, next_cursor: next_cursor,
      filters_applied: { "run_started_at" => run.started_at.iso8601, "severity" => args["severity"], "check_id" => args["check_id"], "include_acknowledged" => args["include_acknowledged"] == true }.compact
    )
  end

  SEVERITY_WEIGHT = { "blocking" => 3, "warning" => 2, "info" => 1 }.freeze
  AMOUNT_KEYS = %w[debit credit net booked expected total amount balance register ledger difference residual].freeze
  VAT_CHECKS = %w[C09 C14].freeze
  MAX_PRIORITIZED = 20
  MAX_RANKED = 500

  private

  # The open anomalies in the order to fix them: severity, then what blocks a closing or a VAT filing, then the amount involved, then how long they have been there.
  # ponytail: ranks the first MAX_RANKED anomalies of the run, in Ruby (a few hundred rows of anomalies, not entry lines); a SQL ranking if runs ever hold thousands.
  def prioritized(findings, acknowledged, run, args)
    rows = findings.reorder(:id).limit(MAX_RANKED).to_a
    first_seen = Accounting::ConsistencyFinding.where(fingerprint: rows.map(&:fingerprint)).group(:fingerprint).minimum(:created_at)
    scored = rows.map { |finding| score(finding, first_seen.fetch(finding.fingerprint, finding.created_at), run) }
    ranked = scored.sort_by { |entry| [ -SEVERITY_WEIGHT.fetch(entry[:finding].severity, 0), entry[:blocks].empty? ? 1 : 0, -entry[:amount], -entry[:age_days], entry[:finding].id ] }
    listed = ranked.first(MAX_PRIORITIZED)
    Agent::ToolResult.build(
      data: listed.each_with_index.map { |entry, index| ranked_row(entry, index + 1, acknowledged) },
      totals: findings.reorder(nil).group(:severity).count.transform_values(&:to_s).merge("ref" => Agent::Refs.build("R19", run.id)), as_of: run.started_at.to_date, truncated: ranked.size > listed.size,
      warnings: ranked.size > listed.size ? [ "Only the first #{MAX_PRIORITIZED} of #{ranked.size} open anomalies are ranked: offer to go on with the next ones." ] : [],
      filters_applied: { "run_started_at" => run.started_at.iso8601, "prioritize" => true, "severity" => args["severity"], "check_id" => args["check_id"] }.compact
    )
  end

  def ranked_row(entry, rank, acknowledged)
    row_for(entry[:finding], acknowledged).merge("priority_rank" => rank, "priority_reasons" => reasons(entry), "age_days" => entry[:age_days],
                                                 "amount_involved" => (Agent::ToolResult.money(entry[:amount]) if entry[:amount].positive?)).compact
  end

  def score(finding, first_seen, run)
    amount = finding.data.slice(*AMOUNT_KEYS).values.filter_map { |value| BigDecimal(value.to_s).abs if value.to_s.match?(/\A-?\d+(\.\d+)?\z/) }.max || BigDecimal("0")
    blocks = []
    blocks << "closing" if finding.severity == "blocking"
    blocks << "vat_filing" if VAT_CHECKS.include?(finding.check_id) || finding.data["invariant"] == "I7" || finding.subject_type == "Accounting::VatDeclaration"
    { finding: finding, amount: amount, blocks: blocks, age_days: [ (run.started_at.to_date - first_seen.to_date).to_i, 0 ].max }
  end

  def reasons(entry)
    [ "severity", *entry[:blocks].map { |block| "blocks_#{block}" }, (entry[:amount].positive? ? "amount" : nil), (entry[:age_days].positive? ? "age" : nil) ].compact
  end

  def row_for(finding, acknowledged)
    { "check" => finding.check_id, "severity" => finding.severity, "subject_type" => finding.subject_type, "message" => finding.message,
      "acknowledged" => acknowledged.include?(finding.fingerprint), "ref" => Agent::Refs.build("R19", finding.id) }
  end
end
