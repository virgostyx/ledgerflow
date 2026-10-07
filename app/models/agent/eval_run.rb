# One execution of a set of cases of the evaluation, in one mode, against one version of the agent (A12).
class Agent::EvalRun < ApplicationRecord
  self.table_name = "agent_eval_runs"

  has_many :results, class_name: "Agent::EvalResult", foreign_key: :run_id, inverse_of: :run, dependent: :delete_all

  enum :status, { running: "running", complete: "complete", budget_exceeded: "budget_exceeded", failed: "failed" }, default: "running"

  validates :mode, inclusion: { in: %w[simulated real] }

  # The run this one is compared with: the last complete one, in the same mode and scope.
  def previous = self.class.complete.where(mode: mode, scope: scope).where.not(id: id).where(started_at: ...started_at).order(:started_at).last
end
