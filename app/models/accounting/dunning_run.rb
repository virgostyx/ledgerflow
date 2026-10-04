# One preparation of reminders (F09): the day, who prepared it, and its items, one per customer. Sent once its items have been dealt with.
class Accounting::DunningRun < ApplicationRecord
  self.table_name = "dunning_runs"

  acts_as_tenant :entity

  enum :status, { prepared: 0, sent: 1 }

  belongs_to :created_by, class_name: "User", optional: true
  has_many   :items, -> { order(:id) }, class_name: "Accounting::DunningItem", foreign_key: :dunning_run_id, inverse_of: :run, dependent: :destroy
end
