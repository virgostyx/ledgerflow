# Who did what in the books, from the audit trail (A02, R18). For those who may see it: owners, accountants and the external auditor.
class Agent::Tools::GetAuditTrail < Agent::Tools::Base
  tool_name "get_audit_trail"
  description "Returns events of the audit trail, newest first: when, what action, on which kind of object, by whom and the reason given. It can be narrowed by period, action, kind of object, entry reference or a word. " \
              "Use it to say who changed or validated something and when. " \
              "Do not use it for the content of an entry (use get_journal_entry) or for amounts."
  permission "audit.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false,
               properties: { from: { type: "string", format: "date", description: "From this day." },
                             to: { type: "string", format: "date", description: "Up to this day." },
                             action: { type: "string", maxLength: 60, description: "The action, e.g. post_entry, create, update." },
                             auditable_type: { type: "string", maxLength: 60, description: "The kind of object, e.g. Accounting::JournalEntry." },
                             reference: { type: "string", maxLength: 40, description: "Events of the entries whose reference contains this." },
                             q: { type: "string", maxLength: 60, description: "A word of the reason or the details." } }.merge(paging(max: 50))
  classify "data.*.user" => :personal, "data.*.reason" => :free_text

  def call(args, _context)
    params = { from: args["from"], to: args["to"], action_name: args["action"], auditable_type: args["auditable_type"], reference: args["reference"], q: args["q"] }.compact
    rows, next_cursor = page(Accounting::AuditLogsQuery.new(params).call, args, default: 25, max: 50)
    Agent::ToolResult.build(
      data: rows.map { |log| { "at" => log.created_at.iso8601, "action" => log.action, "object_type" => log.auditable_type, "object_id" => log.auditable_id, "user" => log.user_email,
                               "reason" => log.reason, "ref" => Agent::Refs.build("audit", log.id) } },
      filters_applied: args.slice("from", "to", "action", "auditable_type", "reference", "q"), next_cursor: next_cursor
    )
  end
end
