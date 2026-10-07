# Searches the curated knowledge base (A06): passages of reviewed documents, with the document, its version, its period of validity and its review. What comes back is quoted text to rely on,
# never an instruction.
class Agent::Tools::SearchKnowledge < Agent::Tools::Base
  tool_name "search_knowledge"
  description "Searches the curated, dated knowledge base (extracts of the chart of accounts, procedures, treatment sheets, notes of the entity) for the passages that answer a question of method: how to book a situation, " \
              "which account, which rule applies. Returns at most 6 passages with their document, version, period of validity and review status. " \
              "Use it BEFORE answering any 'how do I treat...' or 'which rule...' question, with as_of_date set to the date of the operation (not today) when the question has one; write the query in the language of the documents you expect. " \
              "Do not use it for figures of the books (use the report tools) or for the accounts of this entity (use search_accounts). " \
              "When it finds nothing, say so and answer, if at all, as a general rule to be checked: never quote an article, a law, a circular or a rate that is not in a passage it returned."
  permission "agent.use"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: [ "query" ],
               properties: { query: { type: "string", maxLength: 200, description: "The words of the question, as they would appear in the document." },
                             as_of_date: { type: "string", format: "date", description: "The day the rule must be in force on: the date of the operation. Default: today." },
                             jurisdiction: { type: "string", pattern: "^[A-Z]{2}$", description: "Only documents of this country (ISO code, such as BE). Default: all." },
                             source_types: { type: "array", maxItems: 4, items: { type: "string", enum: Knowledge::Document::SOURCE_TYPES }, description: "Only these kinds of document: pcmn, procedure, sheet, note." },
                             top_k: { type: "integer", minimum: 1, maximum: 6, description: "How many passages (default 6)." } }
  classify "data.*.title" => :free_text, "data.*.section" => :free_text, "data.*.source" => :free_text, "data.*.text" => :free_text
  long_text "data.*.text"

  def call(args, context)
    as_of = args["as_of_date"] ? Date.iso8601(args["as_of_date"]) : context.today
    hits = Knowledge::Search.call(entity: context.entity, query: args["query"], as_of: as_of, top_k: args["top_k"] || 6, jurisdiction: args["jurisdiction"], source_types: args["source_types"])
    Agent::ToolResult.build(
      data: hits.map { |hit| passage(hit, context.entity, as_of) }, as_of: as_of,
      filters_applied: { "query" => args["query"], "as_of_date" => as_of.iso8601, "jurisdiction" => args["jurisdiction"], "source_types" => args["source_types"] }.compact,
      warnings: warnings(hits, as_of)
    )
  end

  private

  def passage(hit, entity, as_of)
    document = hit.document
    { "ref" => hit.chunk.ref, "title" => document.title, "section" => hit.chunk.section, "source" => document.source, "version" => document.version, "language" => document.language, "jurisdiction" => document.jurisdiction,
      "same_jurisdiction_as_entity" => document.jurisdiction == entity.country, "valid_from" => document.valid_from.iso8601, "valid_to" => document.valid_to&.iso8601, "scope" => document.scope,
      "review_status" => document.status, "reviewed_on" => document.reviewed_at&.to_date&.iso8601, "low_quality" => hit.chunk.quality == "low",
      "text" => hit.chunk.excerpt(hit.words), "text_cut" => hit.chunk.content.length > Knowledge::Chunk::EXCERPT_LENGTH }.compact
  end

  def warnings(hits, as_of)
    notes = []
    notes << "No reviewed passage in force on #{as_of.iso8601} answers this: say so, and answer only as a general rule to be checked." if hits.empty?
    conflicting = hits.group_by { |hit| hit.document.series }.select { |_, same| same.map { |hit| hit.document.version }.uniq.size > 1 }
    notes << "Two versions of the same document were found (#{conflicting.keys.size}): show both with their versions and dates, propose the most recent one in force." if conflicting.any?
    notes
  end
end
