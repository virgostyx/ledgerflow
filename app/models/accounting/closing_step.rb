# One step of a closing run (F10). A check is evaluated live and the result shown, never trusted from an earlier day; an action is done once its effect
# stands; a manual step needs a person's confirmation and comment; a report step needs its comments. A step in `warning` goes on once acknowledged with a
# comment; a step that does not block may be skipped, with a reason.
class Accounting::ClosingStep < ApplicationRecord
  self.table_name = "closing_steps"

  acts_as_tenant :entity

  enum :kind,   { check: 0, action: 1, manual: 2, report: 3 }, prefix: :kind
  enum :status, { pending: 0, ok: 1, warning: 2, blocked: 3, skipped: 4, done: 5 }

  belongs_to :run, class_name: "Accounting::ClosingRun", foreign_key: :closing_run_id, inverse_of: :steps
  belongs_to :completed_by,    class_name: "User", optional: true
  belongs_to :acknowledged_by, class_name: "User", optional: true

  validates :code, :title, :position, presence: true

  # Settled: nothing more is asked of it. A warning counts once acknowledged; a skipped step only if it does not block.
  def settled?
    ok? || done? || (skipped? && !blocking) || (warning? && acknowledged_at.present?)
  end
end
