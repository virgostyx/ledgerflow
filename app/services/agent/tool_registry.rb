# The tools the model may call, and the one place where a call is run (A02): the permission is checked here, before the tool runs, with the rights the
# person holds now. What goes back to the model is always a result, never an exception or an internal detail.
class Agent::ToolRegistry
  FORBIDDEN = { "error" => "forbidden", "message" => "You do not have access to this information." }.freeze

  # Every tool the agent has, in one list: adding a tool means adding its class here, so that nothing joins the catalog by accident.
  def self.default
    new(%w[GetCompanyContext SearchAccounts SearchPartners GetJournalEntry GetTrialBalance GetLedger GetAgedBalance ListUnreconciled GetBankReconciliation
           GetFinancialStatements GetVatReturn GetDashboardKpis GetConsistencyFindings GetAuditTrail SearchDocuments SearchKnowledge GetFindingContext GetVariation ProposeEntry ProposeTask ProposeNote GetMemoryNotes GetDocumentExtract Calculate].map { |name| "Agent::Tools::#{name}".constantize })
  end

  def initialize(tools = [], timeout: Agent::Config.limits[:max_tool_seconds])
    @tools = tools.index_by(&:tool_name)
    @timeout = timeout
  end

  def tool(name) = @tools[name]

  def definitions = @tools.values.map(&:definition)

  # What the person is shown: only the tools their rights allow (A07/A10), so that a reader is not sent the definitions of the tools that propose. The check at the call stays: this is a saving, not a guard.
  def definitions_for(context) = @tools.values.select { |tool| context.allows?(tool.permission) }.map(&:definition)

  # `security` (Agent::Security) is told of what a defence should notice: a refusal, an argument the tool does not have, a tool that does not exist, free text that looks like
  # an instruction. Without one the registry works the same, it just says nothing.
  def execute(name, args, context, security: nil)
    tool = @tools[name]
    unless tool
      security&.event(:unknown_tool, tool: name)
      return { "error" => "not_found", "message" => "Unknown tool." }
    end
    return forbidden(name, security) unless context.allows?(tool.permission)

    problems = Agent::ArgumentValidator.problems(tool.input_schema, args)
    if problems.any?
      unknown = args.to_h.keys.map(&:to_s) - tool.input_schema.fetch(:properties, {}).keys.map(&:to_s)
      security&.event(:forbidden_argument, tool: name, excerpt: problems.to_sentence) if unknown.any?
      return { "error" => "invalid_arguments", "message" => problems.to_sentence }
    end

    # ponytail: Timeout interrupts the thread, not a query already sent to the database; a statement_timeout per tool if a report ever runs that long.
    result = Timeout.timeout(@timeout) { read_only { tool.new.call(args, context) } }
    result, findings = Agent::Untrusted.clean(tool, result)
    security&.suspicious!(name, findings) if findings.any?
    result
  rescue Agent::ToolError => e
    { "error" => e.code, "message" => e.message }
  rescue Timeout::Error
    { "error" => "timeout", "message" => "The tool took too long. Narrow the period or the filters and try again." }
  rescue StandardError => e
    Rails.logger.error("[agent] tool #{name} failed: #{e.class}")
    { "error" => "internal_error", "message" => "The tool could not answer. Try again, or use the report directly." }
  end

  private

  def forbidden(name, security)
    security&.forbidden!(name)
    FORBIDDEN
  end

  # Whatever a tool's code does, the database refuses a write while it runs (A02: no tool writes to the books). The call runs in a savepoint that is always rolled back: that
  # is what puts the connection back to writable (PostgreSQL cannot leave read-only mode inside a transaction), and a tool that only reads loses nothing by it.
  def read_only
    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      ActiveRecord::Base.connection.execute("SET LOCAL transaction_read_only = on")
      result = yield
      raise ActiveRecord::Rollback
    end
    result
  end
end
