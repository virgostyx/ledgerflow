# A draft the person asks to revise (A11): its current text, to be rewritten with an instruction. Only the person's own drafts.
class Agent::Tools::GetTextDraft < Agent::Tools::Base
  tool_name "get_text_draft"
  description "Gives the current text of one of the person's drafts, to revise it on their instruction (firmer, shorter, in another language). Use it when asked to revise a draft, then call propose_text with revises set to its ID. " \
              "Do not use it to find drafts or for anything else."
  permission "agent.propose"
  tool_version 1
  input_schema type: "object", additionalProperties: false, required: %w[draft_id], properties: { draft_id: { type: "integer", minimum: 1 } }
  classify "data.*.subject" => :free_text, "data.*.body" => :free_text
  long_text "data.*.body"

  def call(args, context)
    draft = Agent::TextDraft.find_by(id: args["draft_id"], user_id: context.user.id) or raise Agent::ToolError.new("not_found", "There is no such draft of yours.")
    Agent::ToolResult.build(data: [ { "draft_id" => draft.id, "kind" => draft.kind, "language" => draft.language, "partner_id" => draft.partner_id, "level" => draft.level, "subject" => draft.subject_line, "body" => draft.body, "status" => draft.status }.compact ],
                            warnings: draft.draft? ? [] : [ "This draft is no longer open: it cannot be revised." ])
  end
end
