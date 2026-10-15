# Where the integrity of the books stands (B03c): the last anchor, the last check and what it found, the certificates issued, the keys. No accounting figure, no name of a person.
class Agent::Tools::GetIntegrityStatus < Agent::Tools::Base
  tool_name "get_integrity_status"
  description "Where the integrity of the books stands: last anchor, last check, certificates, keys. For 'are the books verified?'. Not for figures."
  permission "integrity.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false, properties: {}

  def call(_args, context)
    raise Agent::ToolError.new("forbidden", "The integrity certificates are not turned on for this entity.") unless context.entity.feature?(:b03c)

    anchor = Ledger::Anchor.chronological.last
    run = IntegrityCheckRun.recent.first
    keys = Ledger::SigningKey.group(:status).count
    Agent::ToolResult.build(
      data: [ { "last_anchor" => (anchor && { "number" => anchor.number, "at" => anchor.anchored_at.utc.iso8601, "entries" => anchor.entries_count, "timestamped" => anchor.timestamp_token.present? }),
                "anchors" => Ledger::Anchor.count, "last_check" => (run && { "mode" => run.mode, "at" => run.finished_at.utc.iso8601, "findings" => run.findings_count }),
                "certificates" => IntegrityCertificate.where(revoked_at: nil).count, "keys" => { "active" => keys.fetch("active", 0), "retired" => keys.fetch("retired", 0), "revoked" => keys.fetch("revoked", 0) },
                "timestamp_authority" => Ledger::Timestamping.configured?(context.entity) } ],
      filters_applied: {}, warnings: (run && !run.clean? ? [ "The last check found #{run.findings_count} divergences: see the consistency findings (C23)." ] : [])
    )
  end
end
