# The e-mails of the tasks and comments (F08): a task assigned, a mention, a task due.
class Accounting::TaskMailer < ApplicationMailer
  def task_assigned(notification) = notify(notification, "A task was assigned to you")
  def mention(notification) = notify(notification, "You were mentioned in a comment")
  def task_due(notification) = notify(notification, "A task is due")
  def digest(notification) = notify(notification, "Your tasks of the day")
  def external_reply(notification) = notify(notification, "A third party answered your question")

  private

  def notify(notification, subject)
    @notification = notification
    @entity = notification.entity
    @task = notification.subject.is_a?(Accounting::Task) ? notification.subject : (notification.subject.try(:commentable) if notification.subject.try(:commentable).is_a?(Accounting::Task))
    @comment = notification.subject if notification.subject.is_a?(Accounting::Comment)
    mail(to: notification.user.email, subject: "[LedgerFlow] #{subject} — #{@entity.legal_name}", template_name: "notification")
  end
end
