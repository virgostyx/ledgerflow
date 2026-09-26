# Delivers a queued Accounting::PaymentReminder and records the outcome. Takes the id, not the record: a job runs with
# no tenant, and loading a tenant-scoped record through GlobalID would raise.
class Accounting::PaymentReminderJob < ApplicationJob
  queue_as :default

  def perform(reminder_id)
    reminder = ActsAsTenant.without_tenant { Accounting::PaymentReminder.find(reminder_id) }
    return unless reminder.queued?

    ActsAsTenant.with_tenant(reminder.entity) do
      Accounting::PaymentReminderMailer.payment_reminder(reminder).deliver_now
      reminder.update!(status: :sent, sent_at: Time.current, error: nil)
    rescue StandardError => e
      reminder.update!(status: :failed, error: e.message.truncate(500))
    end
  end
end
