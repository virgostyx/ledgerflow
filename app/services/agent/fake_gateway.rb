# Stands in for the model in every test, and on a development machine: it replays what it was given and remembers what it was asked. No network.
class Agent::FakeGateway
  class ScriptExhausted < StandardError; end

  attr_reader :requests

  # A gateway that answers every question with the same plain text, for the panel on a development machine.
  def self.simulated
    new(Enumerator.produce { Agent::Response.new(stop_reason: "end_turn", content: [ { type: "text", text: "This is a simulated answer: the live provider is off outside production." } ], usage: { input_tokens: 0, output_tokens: 0 }, model: "simulated") })
  end

  def initialize(script)
    @script = script.respond_to?(:next) ? script : script.each
    @requests = []
  end

  def call(system:, messages:, tools:, task: :chat_default)
    @requests << { system: system, messages: messages, tools: tools, task: task }
    response = @script.next
    yield response.text if block_given? && response.text.present?
    response
  rescue StopIteration
    raise ScriptExhausted, "the scripted answers are over (#{@requests.size} requests)"
  end
end
