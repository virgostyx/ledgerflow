# "Check" on an answer (A05): the same tool calls, with the same arguments, on the day of the answer, with the rights of the person now. It says whether the figures the answer rested on are still the
# ones the books give, and, if not, which amounts appeared or disappeared; and whether the books have moved since, even when the figures asked about have not.
module Agent::Verification
  Change = Data.define(:tool, :arguments, :added, :removed, :error)
  Result = Data.define(:changes, :books_moved) do
    def valid? = changes.empty?
  end

  def self.call(message:, context:, registry: Agent::ToolRegistry.default)
    replay_context = Agent::Context.build(user: context.user, entity: context.entity, locale: context.locale, today: message.created_at.to_date)
    changes = message.tool_calls.sort_by(&:id).select { |call| call.status == "ok" }.filter_map { |call| compare(call, replay_context, registry) }
    Result.new(changes: changes, books_moved: message.ledger_version.present? && message.ledger_version != Agent::LedgerVersion.current)
  end

  def self.compare(call, context, registry)
    arguments = JSON.parse(call.arguments.presence || "{}")
    result = registry.execute(call.tool, arguments, context)
    return Change.new(tool: call.tool, arguments: arguments, added: [], removed: [], error: result["error"]) if result["error"]

    now = Agent::Amounts.of(result.to_json)
    before = Array(call.result_amounts)
    added, removed = now - before, before - now
    Change.new(tool: call.tool, arguments: arguments, added: added, removed: removed, error: nil) if added.any? || removed.any?
  end
  private_class_method :compare
end
