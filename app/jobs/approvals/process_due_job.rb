# Hourly (B01a): reminders, escalations and reroutings of the approvals that wait.
class Approvals::ProcessDueJob < ApplicationJob
  queue_as :default

  def perform = Approvals::ProcessDue.call
end
