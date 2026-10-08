# What was read from one document (A09): the fields the model proposed or a person confirmed, with the page and line each came from, and passages of its text for the questions about its content. The text is
# the one read locally (F03), and it is treated as data: cut, scanned for instructions, masked like everything that leaves.
class Agent::Tools::GetDocumentExtract < Agent::Tools::Base
  PASSAGES = 3
  WINDOW = 3 # lines kept from the first line that holds a word searched

  tool_name "get_document_extract"
  description "Gives what was read from one supporting document: its type, the fields extracted (supplier, VAT number, number, dates, totals) with their state (confirmed, to confirm, not found) and the page and line they came from, " \
              "and, with query, up to 3 passages of its text with their page. Use it to answer questions about a document's content (payment terms, renewal, clauses) quoting at most 25 words with the page, " \
              "or before proposing an entry for a document (document_id is the number of doc:ID). Do not use it to give a legal reading of a text, nor to find documents (search_documents)."
  permission "documents.view"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[document_id],
               properties: { document_id: { type: "integer", minimum: 1, description: "The ID of a document reference (doc:ID)." },
                             query: { type: "string", maxLength: 80, description: "Words to look for in the text of the document." } }
  classify "data.*.name" => :free_text, "data.*.fields.*.value" => :free_text, "data.*.fields.*.snippet" => :free_text, "data.*.passages.*.text" => :free_text
  long_text "data.*.passages.*.text"

  def call(args, _context)
    document = Accounting::Document.find_by(id: args["document_id"]) or raise Agent::ToolError.new("not_found", "There is no such document: find it with search_documents.")
    extraction = Agent::DocumentExtraction.where(document_id: document.id).where.not(status: %w[failed rejected]).order(:id).last
    passages = passages_of(document, args["query"])
    Agent::ToolResult.build(
      data: [ { "name" => document.name, "kind" => document.kind, "status" => document.status, "ref" => Agent::Refs.build("doc", document.id), "extraction" => extraction_row(extraction), "fields" => field_rows(extraction, document), "passages" => passages }.compact ],
      filters_applied: { "document_id" => document.id, "query" => args["query"] }.compact,
      warnings: warnings(document, extraction, passages, args["query"])
    )
  end

  private

  def extraction_row(extraction)
    extraction && { "type" => extraction.document_type, "status" => extraction.status, "engine" => extraction.engine, "entry_allowed" => extraction.entry_allowed?, "coverage" => extraction.coverage }
  end

  # The fields read by the model (to confirm or confirmed), or else those F03 read locally and a person confirmed.
  def field_rows(extraction, document)
    rows = extraction ? extraction.fields.map { |name, field| field_row(name, field, extraction.confirmed? || field["confirmed"]) } : []
    return rows if rows.any?

    document.extracted_data.dig("extraction", "fields").to_h.except("supplier_partner_id").map { |name, field| field_row(name, field.merge("state" => field["confirmed"] ? "ok" : "needs_confirmation"), field["confirmed"]) }
  end

  def field_row(name, field, confirmed)
    { "name" => name, "value" => field["value"], "state" => (confirmed ? "confirmed" : { "ok" => "to_confirm", "needs_confirmation" => "to_confirm_with_care", "not_found" => "not_found" }.fetch(field["state"], "to_confirm")), "page" => field["page"], "snippet" => field["snippet"] }.compact
  end

  def passages_of(document, query)
    pages = document.search_text.to_s.split("\f")
    return [] if pages.empty?

    words = Knowledge::Search.words_of(query)
    candidates = pages.each_with_index.flat_map do |page, index|
      lines = page.lines.map(&:strip).reject(&:empty?)
      lines.each_index.filter_map do |at|
        hits = words.count { |word| I18n.transliterate(lines[at]).downcase.include?(word) }
        { page: index + 1, text: lines[at, WINDOW].join(" ").first(Agent::Untrusted::MAX_LONG_LENGTH), hits: hits } if words.empty? ? at.zero? : hits.positive?
      end
    end
    candidates.max_by(PASSAGES) { |entry| [ entry[:hits], -entry[:page] ] }.sort_by { |entry| entry[:page] }.map { |entry| { "page" => entry[:page], "text" => entry[:text] } }
  end

  def warnings(document, extraction, passages, query)
    notes = []
    notes << "No text was read from this document: the passages are empty. Say so." if document.search_text.blank?
    notes << "Nothing in the text matches the words: say so, do not guess." if query.present? && document.search_text.present? && passages.empty?
    notes << "Part of the document was not read (more pages than the limit): say so." if extraction&.coverage == "partial"
    notes << "The fields have not been read by the assistant yet (or only locally): they are proposals, not data." unless extraction
    notes << "This document gives no entry (it is not an invoice or a credit note): do not propose one." if extraction && !extraction.entry_allowed?
    notes
  end
end
