# F08: a task, about something the user sees (the target is prefilled from the screen it is made from). The assignee is told, unless it is the author.
# attrs: title, description, kind, priority, due_on, assignee_id, target (the record), anomaly_fingerprint, question, external_expires_at.
class Accounting::CreateTask
  def self.call(user:, **attrs)
    ctx = LightService::Context.make(task: nil)
    task = Accounting::Task.new(attrs.merge(author: user))
    return ctx.tap { |c| c.fail!(I18n.t("errors.not_authorized")) } unless Accounting::TaskPolicy.new(user, task).create?
    return ctx.tap { |c| c.fail!(I18n.t("accounting.tasks.errors.target_not_visible")) } if task.target && !Accounting::TaskTargets.visible?(user, task.target)

    if task.save
      Accounting::Notify.call(user: task.assignee, event: "task_assigned", subject: task, data: { by: user.full_name }) if task.assignee && task.assignee != user
      ctx[:task] = task
    else
      ctx.fail!(task.errors.full_messages.to_sentence)
    end
    ctx
  end
end
