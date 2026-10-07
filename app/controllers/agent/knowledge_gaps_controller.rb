# What the knowledge base could not answer (A06): questions without a passage and answers found not useful, by frequency, to say what to add.
class Agent::KnowledgeGapsController < Agent::BaseController
  before_action { authorize :agent, :manage_knowledge? }

  def index
    @gaps = Knowledge::Gap.ranked
  end
end
