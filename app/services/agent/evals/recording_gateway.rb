# Stands between the runner and the model, whichever it is, and keeps what was sent after masking (A12): the evaluation judges what the provider would have received, not what the
# application meant to send.
class Agent::Evals::RecordingGateway
  attr_reader :sent

  def initialize(inner)
    @inner = inner
    @sent = []
  end

  def call(**args, &block)
    @inner.call(**args, &block).tap { |response| @sent << response.sent if response.sent }
  end

  # What the model was shown of the tools' answers, in the last request: it holds every earlier one.
  def tool_results
    Array(@sent.last&.dig(:messages)).flat_map { |message| Array(message[:content]).select { |block| block.is_a?(Hash) && block[:type].to_s == "tool_result" } }.map { |block| block[:content].to_s }
  end

  def payload = @sent.to_json
end
