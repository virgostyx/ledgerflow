# Daily (F08): the assignee of an open task that falls due tomorrow is reminded, once per due date (a task whose due date moves is reminded again).
# Nothing for a closed task or one with nobody assigned. => number of reminders
class Accounting::TaskDueRemindersJob < ApplicationJob
  queue_as :default

  DAYS_BEFORE = 1

  def perform
    Entity.find_each.sum { |entity| ActsAsTenant.with_tenant(entity) { remind } }
  end

  private

  def remind
    due = Date.current + DAYS_BEFORE
    Accounting::Task.open_ones.where(due_on: due).where.not(assignee_id: nil).includes(:assignee).count do |task|
      Accounting::Notify.call(user: task.assignee, event: "task_due:#{task.due_on.iso8601}", subject: task, data: { due_on: task.due_on.iso8601 }).present?
    end
  end
end
