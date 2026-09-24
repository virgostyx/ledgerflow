# Delivers a queued Accounting::InvoiceEmail and records the outcome. Takes the id, not the record: a job runs with
# no tenant, and loading a tenant-scoped record through GlobalID would raise.
class Accounting::InvoiceEmailJob < ApplicationJob
  queue_as :default

  def perform(email_id)
    email = ActsAsTenant.without_tenant { Accounting::InvoiceEmail.find(email_id) }
    return unless email.queued?

    ActsAsTenant.with_tenant(email.entity) do
      Accounting::InvoiceMailer.invoice_email(email).deliver_now
      email.update!(status: :sent, sent_at: Time.current, error: nil)
    rescue StandardError => e
      email.update!(status: :failed, error: e.message.truncate(500))
    end
  end
end
