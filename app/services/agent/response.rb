# What the model answered: why it stopped ("end_turn", "tool_use", ...), its content blocks (text, tool_use, ...), the tokens used and the model that answered; and what was done to
# what was sent (A04): how many values were masked or blocked, by class of data, and what was sent after masking.
Agent::Response = Data.define(:stop_reason, :content, :usage, :model, :redaction, :sent) do
  def initialize(stop_reason:, content:, usage:, model:, redaction: {}, sent: nil) = super

  def text = content.select { |block| block[:type].to_s == "text" }.map { |block| block[:text] }.join
  def tool_uses = content.select { |block| block[:type].to_s == "tool_use" }
end
