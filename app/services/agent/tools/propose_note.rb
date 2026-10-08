# Proposes to remember a fact about the file (A10b). It writes nothing: the person reads the note, corrects it and confirms. The agent never keeps a note of its own accord.
class Agent::Tools::ProposeNote < Agent::Tools::Base
  tool_name "propose_note"
  description "Proposes a short note (500 characters at most) for the person to keep about the whole file, a partner or an account, such as 'this customer always pays at 45 days'. Nothing is saved until the person confirms. " \
              "Use it only when the person asks to remember something, or accepts your offer to. Do not use it to store figures, preferences of display, or anything you inferred without being told."
  permission "agent.propose"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[scope_kind text category],
               properties: { scope_kind: { type: "string", enum: Agent::MemoryNote::SCOPES }, object_id: { type: "integer", minimum: 1, description: "The ID of the partner or account (partner:ID, account:ID); none for the whole file." },
                             text: { type: "string", maxLength: Agent::MemoryNote::MAX_LENGTH }, category: { type: "string", enum: Agent::MemoryNote::CATEGORIES }, valid_until: { type: "string", format: "date", description: "Until when the note holds, if it does not last." },
                             rationale: { type: "string", maxLength: 500, description: "Why this is worth keeping." } }
  classify "data.*.proposal.text" => :free_text, "data.*.proposal.rationale" => :free_text

  def call(args, context)
    result = Agent::Proposals::Note.call(args, context: context, today: context.today)
    raise Agent::ToolError.new("invalid_proposal", "The proposal was not accepted. Correct: #{result.errors.join(' ')}") unless result.valid?

    Agent::ToolResult.build(data: [ { "valid" => true, "proposal" => result.normalized, "next" => "The person sees the note and decides. It is not saved yet." } ], filters_applied: args.slice("scope_kind", "object_id"), warnings: result.warnings)
  end
end
