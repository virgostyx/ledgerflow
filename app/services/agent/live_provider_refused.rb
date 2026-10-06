# Outside production the real provider is never called, so that no real data leaves a development machine (A04). AGENT_ALLOW_LIVE_PROVIDER lifts it for an
# evaluation run on demonstration data.
class Agent::LiveProviderRefused < StandardError
  def initialize = super("The live provider is only reached in production, or with AGENT_ALLOW_LIVE_PROVIDER set for an evaluation on demonstration data.")
end
