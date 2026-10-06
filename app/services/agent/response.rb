# What the model answered: why it stopped ("end_turn", "tool_use", ...), its content blocks (text, tool_use, ...), the tokens used and the model that answered.
Agent::Response = Data.define(:stop_reason, :content, :usage, :model) do
  def text = content.select { |block| block[:type].to_s == "text" }.map { |block| block[:text] }.join
  def tool_uses = content.select { |block| block[:type].to_s == "tool_use" }
end
