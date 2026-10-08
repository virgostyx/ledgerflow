# The notes the people of the file kept (A10b): facts they wrote, for the whole file or for a partner or an account. They are users' words, not the books: quoted as notes, never a source of figures.
class Agent::Tools::GetMemoryNotes < Agent::Tools::Base
  tool_name "get_memory_notes"
  description "Returns the notes people kept about the whole file, or about a partner or an account: what they wrote, the category, who and when. Use it when answering about a partner or an account, or to handle the file as its accountants do, " \
              "and quote a note as 'according to the note of DATE by NAME'. A note is a person's word, not the books: never take an amount from it, and say so when it disagrees with the data. Do not use it to find figures."
  permission "agent.use"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[scope_kind],
               properties: { scope_kind: { type: "string", enum: Agent::MemoryNote::SCOPES }, object_id: { type: "integer", minimum: 1, description: "The ID of the partner or account (partner:ID, account:ID)." } }
  classify "data.*.text" => :free_text, "data.*.author" => :personal
  long_text "data.*.text"

  LABEL = "Note of a user, not verified by the books".freeze

  def call(args, _context)
    kind = args["scope_kind"]
    raise Agent::ToolError.new("invalid_arguments", "object_id is needed for a #{kind}.") if kind != "entity" && args["object_id"].nil?

    notes = Agent::MemoryNote.active.includes(:author).where(scope_kind: "entity").or(Agent::MemoryNote.active.includes(:author).for_scope(kind, args["object_id"])).ordered.limit(20).to_a
    Agent::ToolResult.build(
      data: notes.map { |note| row_for(note) }, filters_applied: args.slice("scope_kind", "object_id"),
      warnings: notes.empty? ? [] : [ "These are notes of users, not the books: quote them as notes, never take an amount from them, and say when one disagrees with the data. Two notes that disagree are both to be shown with their dates." ]
    )
  end

  private

  def row_for(note)
    { "ref" => Agent::Refs.build("note", note.id), "scope" => note.scope_kind, "category" => note.category, "text" => note.text, "author" => note.author.full_name, "written_on" => note.created_at.to_date.iso8601,
      "valid_until" => note.valid_until&.iso8601, "status" => LABEL }.compact
  end
end
