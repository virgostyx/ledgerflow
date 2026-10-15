# B03c: one run of Integrity::SelfCheck for a company: when, how much it looked at, what it found.
class IntegrityCheckRun < ApplicationRecord
  acts_as_tenant :entity

  scope :recent, -> { order(finished_at: :desc, id: :desc) }

  def clean? = findings_count.zero?
end
