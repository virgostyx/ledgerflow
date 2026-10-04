# The guided closing of one fiscal year (F10): 18 steps, from the preparation to the approval. Checks run live and may be run again at any time; what
# is kept is the acknowledgements, the comments, and the snapshot taken when the year closes. A year can be closed, then reopened, and closed again:
# each time is a run.
class Accounting::ClosingRun < ApplicationRecord
  self.table_name = "closing_runs"

  include Accounting::AuditTrailed

  acts_as_tenant :entity

  enum :status, { draft: 0, in_progress: 1, ready: 2, closed: 3, reopened: 4 }

  belongs_to :fiscal_year, class_name: "Accounting::FiscalYear"
  belongs_to :opened_by,   class_name: "User", optional: true
  belongs_to :closed_by,   class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :reopened_by, class_name: "User", optional: true
  has_many   :steps, -> { order(:position) }, class_name: "Accounting::ClosingStep", foreign_key: :closing_run_id, inverse_of: :run, dependent: :destroy
  has_one_attached :bundle # the closing file (R20), kept with its manifest of hashes
  has_one :snapshot, class_name: "Accounting::ClosingSnapshot", foreign_key: :closing_run_id, inverse_of: :run, dependent: :destroy

  # The run being worked on: neither closed nor reopened.
  scope :active, -> { where(status: %i[draft in_progress ready]) }

  # The share of the steps that are settled, in percent.
  def progress = steps.empty? ? 0 : (steps.count(&:settled?) * 100.0 / steps.size).floor
end
