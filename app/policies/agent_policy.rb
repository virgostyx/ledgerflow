# The AI agent's rights (A03): who may ask, have proposals prepared, keep file notes, curate the knowledge base, configure
# the agent and read someone else's conversation. Each one is a line of Permissions::MATRIX; nothing is decided here.
class AgentPolicy < ApplicationPolicy
  def use?                  = can?("agent.use")
  def propose?              = can?("agent.propose")
  def manage_memory?        = can?("agent.memory.manage")
  def manage_knowledge?     = can?("knowledge.manage")
  def configure?            = can?("agent.configure")
  def review_conversations? = can?("agent.conversations.review")
end
