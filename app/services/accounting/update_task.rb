# F08: changes a task. The new assignee is told. Closing and reopening set and clear who closed it and when; the audit trail keeps every change.
class Accounting::UpdateTask
  def self.call(task:, user:, **attrs)
    ctx = LightService::Context.make(task: task)
    return ctx.tap { |c| c.fail!(I18n.t("errors.not_authorized")) } unless Accounting::TaskPolicy.new(user, task).update?

    previous = task.assignee_id
    task.assign_attributes(attrs.except(:target, :target_type, :target_id, :author))
    apply_closing(task, user)
    if task.save
      Accounting::Notify.call(user: task.assignee, event: "task_assigned", subject: task, data: { by: user.full_name }) if task.assignee && task.assignee_id != previous && task.assignee != user
    else
      ctx.fail!(task.errors.full_messages.to_sentence)
    end
    ctx
  end

  def self.apply_closing(task, user)
    return unless task.will_save_change_to_status?

    if task.closed?
      task.completed_at = Time.current
      task.completed_by = user
    else
      task.completed_at = nil
      task.completed_by = nil
    end
  end
  private_class_method :apply_closing
end
