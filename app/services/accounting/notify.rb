# F08: tells a person something, once per event and subject: in the application always, by e-mail when they asked for it. The unique key
# is what keeps a mention from being told twice, however many times the comment is saved. An event that may come back says when in its name
# (`task_due:2026-10-07`, `digest:2026-10-05`): once per date.
# => the notification, or nil when the person had it already
class Accounting::Notify
  MAILED = %w[task_assigned mention task_due digest external_reply].freeze

  def self.call(user:, event:, subject:, data: {})
    notification = Accounting::Notification.create!(user: user, event: event, subject: subject, data: data, channel: :in_app)
    mail(user, event, notification) if MAILED.include?(event.split(":").first)
    notification
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end

  def self.mail(user, event, notification)
    membership = UserEntity.current.find_by(user: user, entity: ActsAsTenant.current_tenant)
    return unless membership&.notify_by_email

    Accounting::TaskMailer.public_send(event.split(":").first, notification).deliver_later
  end
  private_class_method :mail
end
