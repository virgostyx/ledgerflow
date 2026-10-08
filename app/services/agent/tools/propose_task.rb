# Proposes a task to the person (A07, F08): a to-do about an entry, an account, a partner or a document, created with one click. It writes nothing.
class Agent::Tools::ProposeTask < Agent::Tools::Base
  tool_name "propose_task"
  description "Proposes a task (a to-do) for the person to create with one click, optionally about an entry, account, partner or document (target such as entry:12). Use it when something has to be checked or asked and the person asks for it or accepts it. " \
              "Nothing is written by you. Do not use it to correct an entry (propose_entry) or to answer a question."
  permission "agent.propose"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[title kind rationale certainty],
               properties: { title: { type: "string", maxLength: 120 }, kind: { type: "string", enum: Accounting::Task.kinds.keys }, priority: { type: "string", enum: Accounting::Task.priorities.keys },
                             due_on: { type: "string", format: "date" }, target: { type: "string", maxLength: 40, description: "A ref: entry:ID, account:ID, partner:ID or doc:ID." },
                             rationale: { type: "string", maxLength: 1500 }, certainty: { type: "string", enum: Agent::Proposals::Entry::CERTAINTY } }
  classify "data.*.proposal.title" => :free_text, "data.*.proposal.rationale" => :free_text

  def call(args, context)
    result = Agent::Proposals::Task.call(args, context: context, today: context.today)
    raise Agent::ToolError.new("invalid_proposal", "The proposal was not accepted. Correct: #{result.errors.join(' ')}") unless result.valid?

    Agent::ToolResult.build(data: [ { "valid" => true, "proposal" => result.normalized, "next" => "The person sees a card with this proposal and decides. The task does not exist yet." } ], filters_applied: args.slice("kind", "target"))
  end
end
