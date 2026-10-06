# The agent cannot be used right now; `reason` is one of Agent::Access's symbols.
class Agent::Unavailable < StandardError
  attr_reader :reason

  def initialize(reason)
    @reason = reason
    super(reason.to_s)
  end
end
