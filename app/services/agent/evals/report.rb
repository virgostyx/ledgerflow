# The report of a run (A12): what was measured and against which version, how each capability fared, what failed and why, what the gates say and how it compares with the run before.
class Agent::Evals::Report
  def initialize(run) = @run = run

  def to_s
    metrics = @run.metrics
    lines = [ "Evaluation of the agent: #{@run.mode} mode, scope #{@run.scope}, #{@run.runs_per_case} run(s) per case",
              "Version #{@run.manifest_hash} (#{@run.manifest.map { |name, digest| "#{name} #{digest[0, 8]}" }.join(', ')})",
              "Status #{@run.status}: #{@run.cases_passed} of #{@run.cases_total} cases passed" + (metrics["not_run"].to_i.positive? ? ", #{metrics['not_run']} not run (budget)" : ""),
              "Tokens: #{@run.input_tokens} in, #{@run.output_tokens} out" + (@run.budget_tokens ? " (budget #{@run.budget_tokens})" : "") ]
    lines << "By capability: #{metrics['by_capability'].map { |capability, rate| "#{capability} #{Agent::Evals::Metrics.percent(rate)}" }.join(', ')}"
    %w[tool_choice figures_exact].each { |name| lines << "#{name}: #{Agent::Evals::Metrics.percent(metrics[name])}" if metrics[name] }
    lines << "Counters that must stay at 0: " + Agent::Evals::Metrics::ZERO.map { |name| "#{name} #{metrics[name]}" }.join(", ")
    lines << "Unstable cases: #{metrics['unstable'].join(', ')}" if metrics["unstable"].present?
    failures = @run.results.where(passed: false).order(:case_id, :attempt)
    failures.each { |result| lines << "  FAILED #{result.case_id} (attempt #{result.attempt}): #{result.checks.reject { |_, outcome| outcome == true }.map { |check, why| "#{check}: #{why}" }.join(' | ')}" }
    lines << (metrics["gate_failures"].empty? ? "Gates: all passed." : "GATES FAILED:\n" + metrics["gate_failures"].map { |failure| "  - #{failure}" }.join("\n"))
    lines.join("\n")
  end

  def passed? = @run.complete? && @run.metrics["gate_failures"].empty?
end
