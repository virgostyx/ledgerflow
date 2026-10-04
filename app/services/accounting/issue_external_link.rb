# F08: a question to a third party (a client: "what is this payment for?") gives a link, valid until a date, through which they answer in text and
# with files, and see nothing else. The link is for the person who writes to them to send as they see fit: nothing is sent from here.
# => ctx[:token], ctx[:expires_at]
class Accounting::IssueExternalLink
  MAX_DAYS = 60

  def self.call(task:, user:, question:, days: 14)
    ctx = LightService::Context.make(task: task)
    return ctx.tap { |c| c.fail!(I18n.t("errors.not_authorized")) } unless Accounting::TaskPolicy.new(user, task).update?
    return ctx.tap { |c| c.fail!(I18n.t("accounting.tasks.errors.question_blank")) } if question.to_s.strip.blank?

    days = days.to_i.clamp(1, MAX_DAYS)
    ApplicationRecord.transaction do
      task.update!(question: question.strip, external_expires_at: days.days.from_now.end_of_day, kind: :client_question)
      Accounting::AuditLog.record!(auditable: task, action: "task_external_link_issued", user: user, payload: { expires_at: task.external_expires_at.iso8601 })
    end
    ctx[:token] = task.external_link_token
    ctx[:expires_at] = task.external_expires_at
    ctx
  end
end
