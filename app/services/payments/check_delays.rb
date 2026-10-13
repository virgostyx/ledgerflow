# What time does to a payment batch (B01c §6 "Alertes"), run every day for every company that has the supplier payments: a batch said to be loaded in the bank whose debit is not
# found after the third open day following its execution date; a debited batch whose payments are still drafts two days after the debit was confirmed. Each alert is a task and a warning
# to the owners, made once (the task fingerprint) and never repeated.
class Payments::CheckDelays
  OPEN_DAYS_WITHOUT_DEBIT = 3
  DAYS_TO_VALIDATE = 2

  def self.call
    Entity.find_each do |entity|
      next unless entity.feature?(:b01b)

      ActsAsTenant.with_tenant(entity) { new(entity).check }
    end
  end

  def initialize(entity)
    @entity = entity
    @today = Date.current
  end

  def check
    Payments::Batch.where(status: :submitted).includes(:bank_profile).find_each { |batch| no_debit(batch) if no_debit?(batch) }
    Payments::Batch.where(status: %i[debited partially_rejected]).where("debited_at < ?", DAYS_TO_VALIDATE.days.ago).find_each { |batch| not_validated(batch) if drafts?(batch) }
  end

  private

  # The alert starts the day after the third open day: the debit may still show up that day.
  def no_debit?(batch)
    closed = Array(batch.bank_profile&.options&.dig("closed_days"))
    day = batch.requested_execution_date
    OPEN_DAYS_WITHOUT_DEBIT.times { day = Payments::SettlementCalendar.next_open(day + 1, extra_closed: closed) }
    @today > day
  end

  def drafts?(batch) = batch.items.includes(:journal_entry).any? { |item| item.confirmed? && item.journal_entry&.draft? }

  def no_debit(batch) = alert(batch, "payment_batch_no_debit", "No debit found for batch #{batch.reference}",
                              "The batch was said to be loaded in the bank and #{batch.requested_execution_date.strftime('%d/%m/%Y')} was its execution date: look at the statement, or say that it was not authorized.")

  def not_validated(batch) = alert(batch, "payment_batch_not_validated", "Payments of batch #{batch.reference} not validated",
                                   "The debit was confirmed on #{batch.debited_at.to_date.strftime('%d/%m/%Y')}: the entries of its payments are still drafts, and its invoices still open.")

  def alert(batch, key, title, description)
    fingerprint = "#{key}:#{batch.id}"
    return if Accounting::Task.exists?(anomaly_fingerprint: fingerprint)

    Accounting::Task.create!(title: title, description: description, kind: :to_check, priority: :high, target: batch, anomaly_fingerprint: fingerprint)
    UserEntity.owners.current.where(entity_id: @entity.id).includes(:user).each do |membership|
      Accounting::Notify.call(user: membership.user, event: "#{key}:#{batch.id}", subject: batch, data: { message: batch.reference })
    end
  end
end
