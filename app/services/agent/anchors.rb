# Where the amounts of an answer may come from (A05): a tool result of the answer (a calculation included), what the person typed, an earlier answer of the conversation. Anything else is an amount
# nobody gave. The agent computes nothing and invents nothing: an amount that is not anchored is regenerated once, then shown as unverified.
class Agent::Anchors
  MONEY_INPUT = /\A-?\d+\.\d{2}\z/

  def initialize(question:, earlier_answers: [])
    @amounts = Set.new(Agent::Amounts.of(question) + earlier_answers.flat_map { |text| Agent::Amounts.of(text) })
  end

  def add_result(json) = @amounts.merge(Agent::Amounts.of(json))

  # The amounts of a text that no source gave.
  def unanchored(text) = Agent::Amounts.of(text) - @amounts.to_a

  # The values handed to a calculation that look like amounts (two decimals) and that no source gave. A value that is not shaped like an amount (a count, a rate with other decimals) is free, and so is
  # the second factor of a multiplication, which is a rate: `multiply` an anchored amount by 0.21 is a VAT calculation.
  def unanchored_inputs(values, operation: nil)
    checked = operation == "multiply" ? values.first(1) : values
    checked.select { |value| value.match?(MONEY_INPUT) }.map { |value| value.delete_prefix("-") }.reject { |value| @amounts.include?(value) }
  end
end
