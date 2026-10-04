# Delivers one validated item (F09): an e-mail goes out; a letter is rendered and kept, validating it meaning it is printed. Once it is out, the lines
# asked for carry the level and the date, and a follow-up task is left on the customer (F08). A refusal by the mail server (an address that does not
# exist) is a bounce: kept on the item and flagged on the customer, counting as no reminder. Any other error leaves the item to send again.
class Accounting::DeliverDunningItem
  def self.call(item:, user: nil)
    return unless item.queued?

    item.email? ? deliver_email(item) : keep_letter(item)
    done(item, user) if item.sent?
  end

  def self.deliver_email(item)
    message = Accounting::DunningMailer.reminder(item)
    message.deliver_now
    item.update!(status: :sent, sent_at: Time.current, message_id: message.message_id, error: nil)
  rescue Net::SMTPFatalError => e
    item.update!(status: :bounced, error: e.message.truncate(500))
    item.partner.update!(email_bounced_at: Time.current)
  rescue StandardError => e
    item.update!(status: :pending, error: e.message.truncate(500))
  end
  private_class_method :deliver_email

  def self.keep_letter(item)
    item.letter_pdf.attach(io: StringIO.new(Accounting::DunningPdf.new(item, letter: true).render), filename: "reminder-#{item.partner_id}-#{item.run_on}.pdf", content_type: "application/pdf")
    item.update!(status: :sent, sent_at: Time.current, error: nil)
  end
  private_class_method :keep_letter

  def self.done(item, user)
    policy = Accounting::DunningPolicy.for(item.entity)
    Accounting::JournalEntryLine.where(id: item.item_lines.select(:line_id)).update_all(dunning_level: item.level, last_dunned_at: item.sent_at)
    Accounting::Task.create!(title: "Follow up: level #{item.level} reminder to #{item.partner.name}", kind: :client_question, target: item.partner,
                             due_on: item.run_on + policy.follow_up_days, assignee: user, author: user)
    item.run.update!(status: :sent) if item.run.items.where(excluded: false).none? { |i| i.pending? || i.queued? }
  end
  private_class_method :done
end
