# The panel of the AI agent (A01). Every request is checked against Agent::Access first: the feature, the owner's setting, the emergency switch and the right to use
# it, as they are now. A conversation is looked up among the current person's own, in the current entity: anyone else's is not found.
class Agent::BaseController < ApplicationController
  before_action :require_agent!

  SCREEN = %r{\A[\w/#.\-]{1,80}\z}
  REFERENCE = /\A[\w:.\-]{1,60}\z/

  private

  def agent_context(**) = Agent::Context.build(user: current_user, entity: ActsAsTenant.current_tenant, locale: I18n.locale, **)

  def require_agent!
    reason = Agent::Access.check(agent_context)
    render partial: "agent/messages/framed_notice", locals: { reason: reason }, status: :forbidden if reason
  end

  def conversations = Agent::Conversation.visible_to(current_user)

  def find_conversation(id = params[:conversation_id] || params[:id]) = conversations.find(id)
end
