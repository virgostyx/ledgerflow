# What the consistency checks found at their last run (A02, R19): the anomalies to fix, by severity, with the ones already acknowledged left out unless asked.
class Agent::Tools::GetConsistencyFindings < Agent::Tools::Base
  tool_name "get_consistency_findings"
  description "Returns the anomalies found by the consistency checks of the books at their last run: for each, the check, the severity (blocking, warning, info), what it is about and a message. " \
              "Anomalies an accountant already acknowledged are left out unless asked for. Use it for what to fix before a closing or a filing, or to explain an anomaly the person mentions. " \
              "Do not use it to correct anything (the agent cannot) or to read amounts: use the report tools."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false,
               properties: { severity: { type: "string", enum: Accounting::ConsistencyFinding::SEVERITIES, description: "Only this severity." },
                             check_id: { type: "string", pattern: "^C\\d{2}$", maxLength: 3, description: "Only this check, e.g. C04." },
                             include_acknowledged: { type: "boolean", description: "Also the anomalies already acknowledged (default false)." } }.merge(paging(max: 50))
  classify "data.*.message" => :free_text

  def call(args, _context)
    run = Accounting::ConsistencyRun.latest_first.first
    return Agent::ToolResult.build(data: [], filters_applied: args.slice("severity", "check_id"), warnings: [ "The consistency checks have not run yet for this entity." ]) unless run

    findings = run.findings.order(:id)
    findings = findings.where(severity: args["severity"]) if args["severity"]
    findings = findings.where(check_id: args["check_id"]) if args["check_id"]
    acknowledged = Accounting::ConsistencyAcknowledgement.where(fingerprint: findings.select(:fingerprint)).pluck(:fingerprint).to_set
    findings = findings.where.not(fingerprint: acknowledged.to_a) unless args["include_acknowledged"]
    rows, next_cursor = page(findings, args, default: 25, max: 50)
    Agent::ToolResult.build(
      data: rows.map { |finding| row_for(finding, acknowledged) },
      totals: findings.reorder(nil).group(:severity).count.transform_values(&:to_s).merge("ref" => Agent::Refs.build("R19", run.id)),
      as_of: run.started_at.to_date, next_cursor: next_cursor,
      filters_applied: { "run_started_at" => run.started_at.iso8601, "severity" => args["severity"], "check_id" => args["check_id"], "include_acknowledged" => args["include_acknowledged"] == true }.compact
    )
  end

  private

  def row_for(finding, acknowledged)
    { "check" => finding.check_id, "severity" => finding.severity, "subject_type" => finding.subject_type, "message" => finding.message,
      "acknowledged" => acknowledged.include?(finding.fingerprint), "ref" => Agent::Refs.build("R19", finding.id) }
  end
end
