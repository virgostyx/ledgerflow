# Daily (B03b): tells the subscribers of the alerts of "What changed" how many arose since they were last told.
class Changes::NotifyAlertsJob < ApplicationJob
  queue_as :default

  def perform = Changes::NotifyAlerts.call
end
