# B01a: reminders (hours after a level starts, 24 and 48 by default), escalation when the service time of a level is over, and
# rerouting when nobody named can decide any more. The counters belong to the current level and are reset when the request moves on. Reversible.
class AddRemindersAndEscalationToApprovals < ActiveRecord::Migration[8.1]
  def change
    add_column :approval_policies, :reminder_hours, :integer, array: true, null: false, default: [ 24, 48 ]
    add_column :approval_requests, :reminders_sent, :integer, null: false, default: 0
    add_column :approval_requests, :escalated_at, :datetime
    add_reference :approval_requests, :escalated_to, foreign_key: { to_table: :users }
    add_column :approval_requests, :rerouted_at, :datetime
  end
end
