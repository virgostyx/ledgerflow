# Finds supporting documents by words, partner, date or amount (A02, F03): what they are and what was read from them, never their content.
class Agent::Tools::SearchDocuments < Agent::Tools::Base
  tool_name "search_documents"
  description "Searches the supporting documents (invoices, statements, contracts) of this entity by words of their name or of what was read from them, optionally by partner, date or total: returns the name, kind, status and date. " \
              "Use it to find the document behind an invoice or a supplier. " \
              "Do not use it to read a document's content (the agent does not receive it) or to find entries (use get_journal_entry or get_ledger)."
  permission "documents.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false,
               properties: { q: { type: "string", maxLength: 80, description: "Up to 8 words; each must appear in the name or in what was read from the document." },
                             partner_id: { type: "integer", minimum: 1, description: "Only documents about this partner: the ID of a partner reference (partner:ID)." },
                             from: { type: "string", format: "date", description: "Dated from this day." },
                             to: { type: "string", format: "date", description: "Dated up to this day." },
                             min_total: { type: "string", pattern: "^\\d{1,12}(\\.\\d{1,2})?$", description: "Total read from the document, at least, as a decimal such as 100.00." },
                             max_total: { type: "string", pattern: "^\\d{1,12}(\\.\\d{1,2})?$", description: "Total read from the document, at most." } }.merge(paging(max: 50))
  classify "data.*.name" => :free_text

  def call(args, _context)
    documents = Accounting::Document.search(args["q"]).dated(args["from"], args["to"]).amount_between(args["min_total"], args["max_total"]).order(created_at: :desc)
    documents = documents.for_partner(args["partner_id"]) if args["partner_id"]
    rows, next_cursor = page(documents, args, default: 20, max: 50)
    Agent::ToolResult.build(
      data: rows.map { |document| { "name" => document.name, "kind" => document.kind, "status" => document.status, "origin" => document.origin, "added" => document.created_at.to_date.iso8601, "ref" => Agent::Refs.build("doc", document.id) } },
      filters_applied: args.slice("q", "partner_id", "from", "to", "min_total", "max_total"), next_cursor: next_cursor
    )
  end
end
