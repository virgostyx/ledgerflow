# A tool's refusal, in the codes the model is told (A02): forbidden, not_found, invalid_arguments, timeout, too_large, and for a proposal the server refused, invalid_proposal. The registry turns it into a result; nothing internal goes with it.
class Agent::ToolError < StandardError
  CODES = %w[forbidden not_found invalid_arguments timeout too_large invalid_proposal limit_reached].freeze

  attr_reader :code

  def initialize(code, message)
    raise ArgumentError, "unknown error code #{code}" unless CODES.include?(code.to_s)

    @code = code.to_s
    super(message)
  end
end
