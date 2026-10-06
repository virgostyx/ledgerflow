# The tools the model may call, and the one place where a call is run (A02): the permission is checked here, before the tool runs, with the rights the
# person holds now. What goes back to the model is always a result, never an exception or an internal detail.
class Agent::ToolRegistry
  FORBIDDEN = { "error" => "forbidden", "message" => "You do not have access to this information." }.freeze

  def initialize(tools = [], timeout: Agent::Config.limits[:max_tool_seconds])
    @tools = tools.index_by(&:tool_name)
    @timeout = timeout
  end

  def definitions = @tools.values.map(&:definition)

  def execute(name, args, context)
    tool = @tools[name] or return { "error" => "not_found", "message" => "Unknown tool." }
    return FORBIDDEN unless context.allows?(tool.permission)

    problems = Agent::ArgumentValidator.problems(tool.input_schema, args)
    return { "error" => "invalid_arguments", "message" => problems.to_sentence } if problems.any?

    # ponytail: Timeout interrupts the thread, not a query already sent to the database; a statement_timeout per tool if a report ever runs that long.
    Timeout.timeout(@timeout) { tool.new.call(args, context) }
  rescue Timeout::Error
    { "error" => "timeout", "message" => "The tool took too long. Narrow the period or the filters and try again." }
  rescue StandardError => e
    Rails.logger.error("[agent] tool #{name} failed: #{e.class}")
    { "error" => "internal_error", "message" => "The tool could not answer. Try again, or use the report directly." }
  end
end
