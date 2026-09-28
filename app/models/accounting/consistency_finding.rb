class Accounting::ConsistencyFinding < ApplicationRecord
  self.table_name = "accounting_consistency_findings"

  acts_as_tenant :entity

  belongs_to :run, class_name: "Accounting::ConsistencyRun", inverse_of: :findings

  SEVERITIES = %w[blocking warning info].freeze

  def acknowledgement_for(acks) = acks[fingerprint]
end
