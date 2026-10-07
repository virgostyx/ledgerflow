namespace :agent do
  desc "Evaluate the agent: agent:evals[all] or agent:evals[A02]. MODE=simulated (default) or real (needs AGENT_ALLOW_LIVE_PROVIDER, demonstration data only); RUNS=3; BUDGET_TOKENS=200000"
  task :evals, [ :scope ] => :environment do |_task, args|
    run = Agent::Evals::Runner.new(scope: args[:scope] || "all", mode: ENV.fetch("MODE", "simulated"), runs: ENV["RUNS"]&.to_i, budget_tokens: ENV["BUDGET_TOKENS"]&.to_i).call
    report = Agent::Evals::Report.new(run)
    puts report
    exit(1) unless report.passed?
  end
end
