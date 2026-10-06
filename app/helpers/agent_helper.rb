# Whether the agent's panel is offered on this page (A01): the same check as every request to the agent, so that a switched-off agent is hidden everywhere.
module AgentHelper
  def agent_available?
    return @agent_available if defined?(@agent_available)

    entity = ActsAsTenant.current_tenant
    @agent_available = current_user.present? && entity.present? && Agent::Access.check(Agent::Context.build(user: current_user, entity: entity, locale: I18n.locale)).nil?
  end
end
