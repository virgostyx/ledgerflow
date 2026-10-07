# Runs the cases of the evaluation and records what happened (A12). In the simulated mode the model is a script written in the case: it is deterministic, needs no network and runs at every
# integration; it measures the harness (the rights, the masking, the guards, the checks themselves). In the real mode the model is the real one, on the invented dataset only, three times per
# case: a case passes if it passes two times in three, and a case that does not always pass is called unstable. A budget of tokens stops a real run cleanly.
class Agent::Evals::Runner
  CASE_FILES = Dir[Rails.root.join("app/services/agent/evals/cases/*.yml")].sort.freeze
  BOOKS = %w[Accounting::JournalEntry Accounting::JournalEntryLine Accounting::Account Accounting::Partner Accounting::PeriodLock Accounting::Lettering Accounting::Document Accounting::Invoice].freeze

  def initialize(scope: "all", mode: :simulated, runs: nil, budget_tokens: nil, files: CASE_FILES)
    @scope = scope.to_s
    @mode = mode.to_sym
    @runs = runs || (@mode == :real ? 3 : 1)
    @budget = budget_tokens
    @files = files
  end

  def call
    raise "The real mode needs the live provider: set AGENT_ALLOW_LIVE_PROVIDER, on demonstration data only." if @mode == :real && !Agent::ModelGateway.live_allowed?

    @built = Agent::Evals::Dataset.build!
    cases = Agent::Evals::Case.load(@files, facts: Agent::Evals::Dataset.facts, ids: Agent::Evals::Dataset.ids(@built)).select { |kase| @scope == "all" || kase.capability == @scope }
    manifest = Agent::Manifest.current
    run = Agent::EvalRun.create!(mode: @mode.to_s, scope: @scope, manifest_hash: manifest.hash_value, manifest: manifest.components, runs_per_case: @runs, cases_total: cases.size, budget_tokens: @budget, started_at: Time.current)
    entries = []
    cases.each do |kase|
      attempts = Array.new(@runs) { |index| attempt(run, kase, index + 1) }
      entries << [ kase, attempts ]
      break if over_budget?(run)
    end
    finish(run, entries)
  rescue StandardError
    run&.update!(status: :failed, finished_at: Time.current)
    raise
  end

  private

  def over_budget?(run) = @budget && run.input_tokens + run.output_tokens > @budget

  def attempt(run, kase, number)
    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    outcome = play(kase)
    checks = Agent::Evals::Checks.run(kase, outcome)
    passed = checks.values.all?(true)
    tokens = outcome.tokens
    run.update!(input_tokens: run.input_tokens + tokens[0], output_tokens: run.output_tokens + tokens[1])
    run.results.create!(case_id: kase.id, capability: kase.capability, attempt: number, passed: passed, checks: checks, answer: outcome.text, input_tokens: tokens[0], output_tokens: tokens[1],
                        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - began) * 1000).round)
    { checks: checks, passed: passed }
  end

  def finish(run, entries)
    metrics = Agent::Evals::Metrics.compute(entries)
    metrics["gate_failures"] = Agent::Evals::Metrics.gate_failures(metrics, run.previous&.metrics)
    metrics["not_run"] = run.cases_total - entries.size
    run.update!(status: over_budget?(run) && entries.size < run.cases_total ? :budget_exceeded : :complete, finished_at: Time.current, metrics: metrics,
                cases_passed: entries.count { |_, attempts| attempts.count { |a| a[:passed] } * 3 >= attempts.size * 2 })
    run
  end

  # Plays one case as the person would: the question put to the agent, as the person of the case, on the day of the dataset. Everything is cleaned up afterwards.
  def play(kase)
    ActsAsTenant.with_tenant(@built.entity) do
      prepare(kase)
      user = kase.role == "reader" ? @built.reader : @built.accountant
      context = Agent::Context.build(user: user, entity: @built.entity, locale: kase.language, today: Agent::Evals::Dataset::AS_OF)
      conversation = Agent::Conversation.create!(user: user, title: "evaluation #{kase.id}")
      gateway = Agent::Evals::RecordingGateway.new(@mode == :real ? Agent::ModelGateway.new : Agent::FakeGateway.new(script_for(kase)))
      before = books
      answer = error = nil
      begin
        answer = Agent::Runner.new(conversation: conversation, context: context, gateway: gateway).ask(kase.input)
      rescue StandardError => e
        error = e.class.name
      end
      outcome = outcome_of(answer, error, gateway, conversation, before)
      conversation.destroy!
      outcome
    end
  end

  def outcome_of(answer, error, gateway, conversation, before)
    calls = answer ? answer.tool_calls.order(:id).map { |call| { name: call.tool, args: JSON.parse(call.arguments.presence || "{}"), status: call.status, error: call.error } } : []
    Agent::Evals::Outcome.new(text: conversation.reveal(answer&.content.to_s), status: answer&.status || "none", flags: answer&.flags || [], tool_calls: calls, tool_results: gateway.tool_results, payload: gateway.payload,
                              books_before: before, books_after: books, security_kinds: Agent::SecurityEvent.where(conversation_id: conversation.id).pluck(:kind), error: error,
                              tokens: [ answer&.input_tokens.to_i, answer&.output_tokens.to_i ], citations: answer&.citations || [])
  end

  def books = BOOKS.map { |name| name.constantize.count }

  # The settings of the entity for this case: switched on, the terms accepted, and the modes the case asks for (the defaults otherwise).
  def prepare(kase)
    Agent::Consent.accept!(@built.accountant)
    Agent::Setting.for_current_entity.update!(enabled: true, restricted: kase.settings.fetch("restricted", false), data_class_modes: kase.settings.fetch("data_class_modes", {}))
  end

  # The model of the simulated mode: what the case says it does, step by step. A tool step calls the tool; the last step says the answer.
  def script_for(kase)
    kase.script.each_with_index.map do |step, index|
      calls = Array(step["tools"] || (step.key?("tool") ? [ step ] : nil))
      content = step.key?("say") ? [ { type: "text", text: step["say"] } ] : calls.each_with_index.map { |call, n| { type: "tool_use", id: "c#{index}_#{n}", name: call["tool"], input: call.fetch("args", {}) } }
      Agent::Response.new(stop_reason: step.key?("say") ? "end_turn" : "tool_use", content: content, usage: { input_tokens: 0, output_tokens: 0 }, model: "script")
    end
  end
end
