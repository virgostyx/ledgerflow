# Drafts a text for the person (A11): a reminder, a request, a comment on a variation, a summary, a reply, a rewrite. The assistant has no way to send it: the draft waits for a person, who reads it, changes it and uses
# it through the screens that already exist. The server refuses what the policy of the company does not allow, and the runner puts a placeholder where a figure, a date or an invoice number was not given by a tool.
class Agent::Tools::ProposeText < Agent::Tools::Base
  FACT = { type: "object", additionalProperties: false, required: %w[label value], properties: { label: { type: "string", maxLength: 80 }, value: { type: "string", maxLength: 120 }, ref: { type: "string", maxLength: 80, description: "The ref the value came from." } } }.freeze

  tool_name "propose_text"
  description "Drafts a text for the person to read, change and use: a customer reminder (dunning_letter), a request for documents (client_request), a comment on a variation (variation_comment), a summary, a reply to a pasted e-mail (reply_email) or a rewrite " \
              "of their own text. Call get_writing_context first, write in the language of the recipient, follow the company profile, and use only amounts, dates and invoice numbers the tools gave: where something is missing write [To complete: what]. " \
              "Never add a promise, a deadline, interest, an indemnity or a threat that you were not given or that the policy does not allow. Nothing is sent: you cannot send. Do not use it to answer a question."
  permission "agent.propose"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[kind language body],
               properties: { kind: { type: "string", enum: Agent::TextDraft::KINDS }, language: { type: "string", enum: Agent::TextDraft::LANGUAGES }, subject: { type: "string", maxLength: 200 }, body: { type: "string", maxLength: Agent::Proposals::Text::MAX_BODY },
                             partner_id: { type: "integer", minimum: 1, description: "The partner it is for (partner:ID)." }, level: { type: "integer", minimum: 1, maximum: 3, description: "The level of a reminder." },
                             facts: { type: "array", maxItems: 30, items: FACT, description: "The data used, each with its ref." }, revises: { type: "integer", minimum: 1, description: "The ID of the draft this one replaces (a new version)." } }
  classify "data.*.proposal.subject" => :free_text, "data.*.proposal.body" => :free_text, "data.*.proposal.facts.*.value" => :free_text
  long_text "data.*.proposal.body"

  def call(args, context)
    result = Agent::Proposals::Text.call(args, context: context, today: context.today)
    raise Agent::ToolError.new("invalid_proposal", "The text was not accepted. Correct: #{result.errors.join(' ')}") unless result.valid?

    Agent::ToolResult.build(data: [ { "valid" => true, "proposal" => result.normalized, "next" => "The person sees the draft and decides what to do with it. It is not sent, and you cannot send it." } ],
                            filters_applied: args.slice("kind", "partner_id", "level"), warnings: result.warnings)
  end
end
