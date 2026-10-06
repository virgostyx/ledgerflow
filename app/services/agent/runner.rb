# Answers one question (A01): builds the messages, asks the model, runs the tools it asks for through the registry, and loops until it answers or a limit is
# reached. The loop is written out, not left to the SDK, so that the rights, the stop button and the limits are checked at every step. It reports what happens
# through the block it is given: :text, :tool_start, :tool_end, :done.
class Agent::Runner
  LIMIT_NOTICE  = "I stopped before finishing: the limit of this question was reached. What I established is above; I could not verify the rest.".freeze
  TOOLS_NOTICE  = "I stopped because the tools are not answering. Try again in a moment, or use the reports directly.".freeze
  ACCESS_NOTICE = "I stopped because you no longer have access to the agent.".freeze

  def initialize(conversation:, context:, gateway: Agent::ModelGateway.default, registry: Agent::ToolRegistry.default, limits: {})
    @conversation = conversation
    @context      = context
    @gateway      = gateway
    @registry     = registry
    @limits       = Agent::Config.limits.merge(limits)
  end

  def ask(question, stop: -> { false }, &on_event)
    ActsAsTenant.with_tenant(@context.entity) { answer(question, stop, on_event) }
  end

  private

  def answer(question, stop, on_event)
    Agent::Access.check!(@context)
    @on_event = on_event
    @stop = stop
    @redactor = Agent::Redactor.new(setting: Agent::Setting.find_by(entity: @context.entity) || Agent::Setting.new(entity: @context.entity), conversation: @conversation)
    @redaction = Hash.new { |hash, data_class| hash[data_class] = Hash.new(0) }
    @texts, @usage, @model, @latency_ms, @tool_calls, @tool_errors, @tool_log = [], Hash.new(0), nil, 0, 0, 0, []
    @security = Agent::Security.new(conversation: @conversation, context: @context)
    messages = history + [ { role: "user", content: question } ]
    @conversation.messages.create!(role: "user", content: question)

    finish(*run(messages))
  end

  # Returns [status, notice]: how the answer ends, and a notice to add to the text when it did not end by itself.
  def run(messages)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    turns = 0
    loop do
      return [ :stopped, nil ] if @stop.call
      return [ :complete, LIMIT_NOTICE ] if turns >= @limits[:max_turns] || Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= @limits[:max_seconds]
      return [ :complete, ACCESS_NOTICE ] if Agent::Access.check(@context)

      response = ask_model(messages)
      turns += 1
      @texts << response.text if response.text.present?
      return [ :complete, nil ] unless response.stop_reason == "tool_use"

      messages << { role: "assistant", content: response.content.map { |block| normalise(block) } }
      outcome = run_tools(response.tool_uses, messages)
      return outcome if outcome
    end
  end

  def ask_model(messages)
    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = @gateway.call(system: Agent::SystemPrompt.build(@context), messages: messages.deep_dup, tools: @registry.definitions, redactor: @redactor) { |piece| emit(type: :text, text: Agent::ResponseGuard.clean(piece).first) }
    @latency_ms += ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - began) * 1000).round
    @model = response.model
    @sent = response.sent
    response.redaction.each { |data_class, counts| counts.each { |how, number| @redaction[data_class.to_s][how.to_s] += number } }
    @usage[:input_tokens]  += response.usage[:input_tokens].to_i
    @usage[:output_tokens] += response.usage[:output_tokens].to_i
    response
  end

  # All the results of one turn go back in a single message, in the order of the calls. Returns an outcome to end the answer, or nil to go on.
  def run_tools(calls, messages)
    results = []
    calls.each do |call|
      return [ :stopped, nil ] if @stop.call
      return [ :complete, LIMIT_NOTICE ] if @tool_calls >= @limits[:max_tool_calls]

      results << run_tool(call)
      return [ :complete, TOOLS_NOTICE ] if @tool_errors >= @limits[:max_tool_errors]
    end
    messages << { role: "user", content: results }
    nil
  end

  def run_tool(call)
    input = reveal(call[:input].to_h.deep_stringify_keys) # the model only knows tokens: the tool needs the real value
    emit(type: :tool_start, name: call[:name], input: input)
    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @registry.execute(call[:name], input, @context, security: @security)
    error = result["error"]
    @tool_calls += 1
    @tool_errors = error ? @tool_errors + 1 : 0
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - began) * 1000).round
    @tool_log << { tool: call[:name], arguments: input.to_json, status: error ? "error" : "ok", error: error, row_count: result["row_count"], truncated: result["truncated"] == true, duration_ms: duration_ms }
    emit(type: :tool_end, name: call[:name], error: error, duration_ms: duration_ms)
    { type: "tool_result", tool_use_id: call[:id], content: result.to_json, is_error: error.present? }
  end

  def finish(status, notice)
    content, removed = Agent::ResponseGuard.clean((@texts + [ notice ]).compact.join("\n\n"))
    removed.each { |kind| @security.event(kind) }
    @security.flag("content_removed") if removed.any?
    @security.event(:limit_reached) if notice == LIMIT_NOTICE
    @conversation.pseudonym_table.unknown_tokens(content).each { |token| @security.event(:invented_token, excerpt: token) }
    message = @conversation.messages.create!(role: "assistant", content: content, status: status, model: @model, latency_ms: @latency_ms, flags: @security.flags,
                                             redaction_stats: @redaction.transform_values(&:to_h), sent_payload: @sent&.to_json,
                                             input_tokens: @usage[:input_tokens], output_tokens: @usage[:output_tokens])
    record_tool_calls(message)
    emit(type: :done, message: message)
    message
  end

  # Each call is kept on the answer it served and written in the entity's audit trail: the tool and the outcome, never the arguments (they are in the encrypted table).
  def record_tool_calls(message)
    @tool_log.each do |call|
      message.tool_calls.create!(call)
      Accounting::AuditLog.record!(auditable: message, action: "agent_tool_call", user: @context.user, payload: { tool: call[:tool], status: call[:status], error: call[:error] }.compact)
    end
  end

  # Earlier turns of the talk, as plain text. An answer that was stopped or failed is not sent back to the model.
  def history
    @conversation.messages.where(role: %w[user assistant], status: "complete").order(:id).map { |message| { role: message.role, content: message.content } }
  end

  def normalise(block)
    block[:type].to_s == "tool_use" ? block.merge(input: block[:input].to_h.deep_stringify_keys) : block
  end

  def reveal(value)
    case value
    when Hash   then value.transform_values { |inner| reveal(inner) }
    when Array  then value.map { |inner| reveal(inner) }
    when String then @conversation.reveal(value)
    else value
    end
  end

  def emit(event) = @on_event&.call(event)
end
