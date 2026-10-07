# Everything the agent needs to explain an anomaly of the consistency checks (A08): the anomaly and its figures, what it is about, the anomalies that share its subject, the recent audit events on it, whether it is
# still there and whether the books moved since the check ran, and the diagnostic protocol that applies (with its validation status). It reads; it corrects nothing.
class Agent::Tools::GetFindingContext < Agent::Tools::Base
  tool_name "get_finding_context"
  description "Gives the context of one anomaly of the consistency checks: its data, its object, the other anomalies on it, recent audit events (if the person may see them), whether it is still there and whether the books changed since the check ran, " \
              "whether it was acknowledged and why, and the diagnostic protocol for this kind of anomaly (causes, checks to make, steps to correct with their screens, when to ask an accountant). " \
              "Use it first when asked about an anomaly, with the finding_id of its R19 reference (R19:ID) from get_consistency_findings, and follow the protocol; with protocol_id alone for a gap with no anomaly (I5, I7, R04) or a variation. Do not use it to list anomalies or correct anything."
  permission "reports.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false,
               properties: { finding_id: { type: "integer", minimum: 1, description: "The ID in the R19 reference of the anomaly (R19:ID)." },
                             protocol_id: { type: "string", pattern: "^[A-Za-z0-9_]{1,12}$", description: "Only the diagnostic protocol of: a check (C04), an invariant (I2, I5, I6, I7, I11), R04 (aged balance gap) or variation." } }
  classify "data.*.finding.message" => :free_text, "data.*.acknowledgement.comment" => :free_text, "data.*.related.*.message" => :free_text

  SUBJECT_REFS = { "Accounting::JournalEntry" => "entry", "Accounting::Account" => "account", "Accounting::Partner" => "partner", "Accounting::VatDeclaration" => "vat", "Accounting::Document" => "doc" }.freeze
  AMOUNT_KEYS = %w[debit credit net booked expected total amount balance register ledger difference residual].freeze

  def call(args, context)
    return protocol_only(args["protocol_id"]) if args["protocol_id"] && !args["finding_id"]
    return { "error" => "invalid_arguments", "message" => "Give a finding_id or a protocol_id." } unless args["finding_id"]

    finding = Accounting::ConsistencyFinding.includes(:run).find_by(id: args["finding_id"])
    return { "error" => "not_found", "message" => "No anomaly with this ID." } unless finding

    playbook = Agent::Playbooks.for_finding(finding.check_id, finding.data)
    acknowledgement = Accounting::ConsistencyAcknowledgement.find_by(fingerprint: finding.fingerprint)
    still = still_present?(finding)
    changed = books_changed_since?(finding.run)
    Agent::ToolResult.build(
      data: [ { "finding" => finding_row(finding), "subject" => subject_row(finding), "acknowledgement" => acknowledgement_row(acknowledgement), "related" => related(finding),
                "audit_events" => audit_events(finding, context), "still_present" => still, "books_changed_since_check" => changed,
                "protocol" => playbook&.to_h_for_tool }.compact ],
      as_of: finding.run.started_at.to_date, filters_applied: { "finding_id" => finding.id },
      warnings: warnings(playbook, acknowledgement, still, changed, context)
    )
  end

  private

  def protocol_only(id)
    playbook = Agent::Playbooks.find(id)
    return { "error" => "not_found", "message" => "No diagnostic protocol with this id." } unless playbook

    Agent::ToolResult.build(data: [ { "protocol" => playbook.to_h_for_tool } ], filters_applied: { "protocol_id" => id },
                            warnings: playbook.validated ? [] : [ "The protocol has not been validated by an accountant: say so, and lower your certainty accordingly." ])
  end

  def finding_row(finding)
    { "ref" => Agent::Refs.build("R19", finding.id), "check" => finding.check_id, "check_title" => Accounting::Consistency::Check.registry.find { |check| check.check_id == finding.check_id }&.title,
      "severity" => finding.severity, "message" => finding.message, "found_at" => finding.created_at.to_date.iso8601, "data" => normalise(finding.data) }.compact
  end

  def normalise(data)
    data.to_h { |key, value| [ key, AMOUNT_KEYS.include?(key) && value.to_s.match?(/\A-?\d+(\.\d+)?\z/) ? Agent::ToolResult.money(value) : value ] }
  end

  def subject_row(finding)
    return unless finding.subject_type

    ref = if SUBJECT_REFS.key?(finding.subject_type) then Agent::Refs.build(SUBJECT_REFS[finding.subject_type], finding.subject_id)
    elsif finding.subject_type == "Accounting::FiscalYear" then Agent::Refs.build("R07", finding.subject_id)
    end
    { "type" => finding.subject_type.demodulize, "ref" => ref }.compact
  end

  def acknowledgement_row(acknowledgement)
    acknowledgement && { "comment" => acknowledgement.comment, "on" => acknowledgement.acknowledged_at.to_date.iso8601 }
  end

  # The other anomalies of the same run on the same object, or of the same check: several anomalies often have one cause.
  def related(finding)
    same = finding.run.findings.where.not(id: finding.id).where(subject_type: finding.subject_type, subject_id: finding.subject_id).limit(10)
    same = finding.run.findings.where.not(id: finding.id).where(check_id: finding.check_id).limit(10) if same.empty?
    same.map { |other| { "ref" => Agent::Refs.build("R19", other.id), "check" => other.check_id, "severity" => other.severity, "message" => other.message } }
  end

  def audit_events(finding, context)
    return unless context.allows?("audit.view") && finding.subject_type

    Accounting::AuditLog.where(auditable_type: finding.subject_type, auditable_id: finding.subject_id).order(created_at: :desc).limit(10)
      .map { |event| { "action" => event.action, "on" => event.created_at.to_date.iso8601, "ref" => Agent::Refs.build("audit", event.id) } }
  end

  # Runs the check again, read only: is the anomaly still there? nil when it cannot be told.
  def still_present?(finding)
    check = Accounting::Consistency::Check.registry.find { |klass| klass.check_id == finding.check_id }
    check && check.new.call.any? { |found| found.fingerprint == finding.fingerprint }
  rescue StandardError
    nil
  end

  def books_changed_since?(run) = Accounting::JournalEntry.where("updated_at > ?", run.started_at).exists?

  def warnings(playbook, acknowledgement, still, changed, context)
    notes = []
    notes << "No diagnostic protocol exists for this check: apply the general approach and lower your certainty." unless playbook
    notes << "The protocol has not been validated by an accountant: say so, and lower your certainty accordingly." if playbook && !playbook.validated
    notes << "A person acknowledged this anomaly: say so and recall the comment." if acknowledgement
    notes << "The anomaly is no longer found by the check: the books changed since it was raised. Say so." if still == false
    notes << "The books changed since the check ran: say so, and base the explanation on what you read now." if changed
    notes << "The audit trail is not shown: the person has no right to it. Say what could not be checked." unless context.allows?("audit.view")
    notes
  end
end
