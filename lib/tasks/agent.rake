namespace :agent do
  desc "Evaluate the agent: agent:evals[all] or agent:evals[A02]. MODE=simulated (default) or real (needs AGENT_ALLOW_LIVE_PROVIDER, demonstration data only); RUNS=3; BUDGET_TOKENS=200000"
  task :evals, [ :scope ] => :environment do |_task, args|
    run = Agent::Evals::Runner.new(scope: args[:scope] || "all", mode: ENV.fetch("MODE", "simulated"), runs: ENV["RUNS"]&.to_i, budget_tokens: ENV["BUDGET_TOKENS"]&.to_i).call
    report = Agent::Evals::Report.new(run)
    puts report
    exit(1) unless report.passed?
  end

  desc "Evaluate the reading of documents on the invented corpus: agent:evals:documents[100]. MODE=simulated (default, an oracle) or real"
  task "evals:documents", [ :count ] => :environment do |_task, args|
    report = Agent::Evals::Documents.run(count: (args[:count] || 100).to_i, mode: ENV.fetch("MODE", "simulated"))
    metrics = report.metrics
    puts "Reading of documents (#{report.mode}): #{metrics['documents']} documents, #{metrics['unreadable']} not read"
    puts "Total with high confidence right: #{metrics['total_high_confidence'].inspect}, numeric fields right: #{metrics['numeric_fields'].inspect}, type right: #{metrics['document_type'].inspect}"
    puts "Values kept that are not in the document: #{metrics['invented_kept']}; sure but wrong: #{metrics['wrong_but_sure']}; changed by an instruction: #{metrics['injection_effect']}"
    puts "Calibration: #{metrics['calibration'].inspect}"
    puts(report.passed? ? "Gates: all passed." : "GATES FAILED:\n" + report.failures.map { |failure| "  - #{failure}" }.join("\n"))
    exit(1) unless report.passed?
  end
end
