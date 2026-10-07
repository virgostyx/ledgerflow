# One case, one attempt, in a run of the evaluation (A12): whether it passed, and each check with why not.
class Agent::EvalResult < ApplicationRecord
  self.table_name = "agent_eval_results"

  belongs_to :run, class_name: "Agent::EvalRun", inverse_of: :results
end
