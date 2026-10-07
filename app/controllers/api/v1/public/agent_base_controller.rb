# What the agent's endpoints of the public API share (A01): the same checks as the panel on every call (the assistant on for the entity, the terms accepted, the emergency switch, the
# right of the owner of the token), conversations looked up among the owner's own in the entity, and how a conversation is written out.
class Api::V1::Public::AgentBaseController < Api::V1::Public::BaseController
  before_action :require_agent!

  SCREEN = Agent::BaseController::SCREEN
  REFERENCE = Agent::BaseController::REFERENCE
  UNAVAILABLE = {
    disabled_platform: [ :service_unavailable, "The assistant is switched off for the moment.", "assistant-unavailable" ],
    feature_off: [ :forbidden, "The assistant is not turned on for this entity.", "agent-not-enabled" ],
    not_enabled: [ :forbidden, "The assistant is not turned on for this entity: an owner turns it on in its settings.", "agent-not-enabled" ],
    consent_missing: [ :forbidden, "The assistant is waiting for an owner to accept the data processing terms for this entity.", "agent-not-enabled" ],
    forbidden: [ :forbidden, "The owner of this token has no right to use the assistant.", "forbidden" ]
  }.freeze

  private

  def agent_context = Agent::Context.build(user: @api_client.owner, entity: ActsAsTenant.current_tenant, locale: :en)

  def require_agent!
    reason = Agent::Access.check(agent_context)
    return unless reason

    status, detail, slug = UNAVAILABLE.fetch(reason)
    problem(status, "Assistant unavailable", detail: detail, slug: slug)
  end

  def conversations = Agent::Conversation.visible_to(@api_client.owner)

  def etag_of(conversation) = etag_for("agent_conversation", conversation.id, conversation.updated_at.iso8601(6), conversation.messages.maximum(:id))

  def conversation_json(conversation, messages: false)
    data = { id: conversation.id, title: conversation.title, status: conversation.status, origin_screen: conversation.origin_screen,
             answering: conversation.answering_since.present? && conversation.answering_since > Agent::Quota::STALE_AFTER.ago,
             created_at: conversation.created_at.iso8601, updated_at: conversation.updated_at.iso8601 }
    data[:messages] = conversation.messages.where(role: %w[user assistant]).order(:id).map { |message| message_json(conversation, message) } if messages
    data
  end

  # What the person reads: the names back in place of the tokens the model used.
  def message_json(conversation, message)
    { id: message.id, role: message.role, content: conversation.reveal(message.content), status: message.status, flags: message.flags, created_at: message.created_at.iso8601 }
  end
end
