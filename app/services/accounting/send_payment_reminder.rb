# Records and queues the payment reminder of one customer: the level, the overdue invoices and what is due on each are
# worked out here (Accounting::OverdueReminders), never taken from the caller. Accounting::PaymentReminderJob sends it.
class Accounting::SendPaymentReminder
  SUBJECTS = { 1 => "Payment reminder", 2 => "Second reminder", 3 => "Formal notice" }.freeze

  def self.call(partner:, recipient:, user:, as_of: Date.current)
    ctx = LightService::Context.make(partner: partner, reminder: nil)
    row = Accounting::OverdueReminders.call(as_of: as_of).find { |r| r.partner == partner }
    return ctx.tap { |c| c.fail!(I18n.t("accounting.payment_reminders.errors.nothing_overdue")) } unless row
    return ctx.tap { |c| c.fail!(reminded_message(partner, row)) } unless row.remindable

    reminder = Accounting::PaymentReminder.new(partner: partner, sent_by: user, level: row.level, recipient: recipient.to_s.strip,
                                               subject: "#{SUBJECTS.fetch(row.level)}: overdue invoices from #{partner.entity.legal_name}")
    ApplicationRecord.transaction do
      reminder.save!
      row.invoices.each { |invoice| reminder.items.create!(invoice: invoice, amount_due: invoice.remaining_amount) }
    end
    Accounting::PaymentReminderJob.perform_later(reminder.id)
    ctx[:reminder] = reminder
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx.tap { |c| c.fail!(e.message.delete_prefix("Validation failed: ")) }
  end

  def self.reminded_message(partner, row)
    I18n.t("accounting.payment_reminders.errors.already_reminded",
           date: Accounting::DatePresenter.new(row.last_reminder.created_at.to_date).format,
           days: Accounting::OverdueReminders::MIN_DAYS_BETWEEN)
  end
  private_class_method :reminded_message
end
