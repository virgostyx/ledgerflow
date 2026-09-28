class Accounting::ConsistencyRun < ApplicationRecord
  self.table_name = "accounting_consistency_runs"

  acts_as_tenant :entity

  has_many :findings, class_name: "Accounting::ConsistencyFinding", foreign_key: :run_id, inverse_of: :run, dependent: :delete_all

  scope :latest_first, -> { order(started_at: :desc, id: :desc) }
end
