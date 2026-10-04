# Daily (F08): for each person who asked for it (`notify_daily_digest` of their access), one summary of what is theirs: open tasks, those overdue, those
# due within three days. Nothing is sent when there is nothing to say; once per day per person. => number of summaries
class Accounting::DailyTaskDigestJob < ApplicationJob
  queue_as :default

  def perform
    Entity.find_each.sum { |entity| ActsAsTenant.with_tenant(entity) { digests(entity) } }
  end

  private

  def digests(entity)
    UserEntity.current.where(entity_id: entity.id, notify_daily_digest: true).includes(:user).count do |membership|
      user = membership.user
      tasks = Accounting::Task.visible_to(user).open_ones.where(assignee_id: user.id)
      counts = { open: tasks.count, overdue: tasks.overdue.count, soon: tasks.where(due_on: Date.current..Date.current + 3).count }
      next false if counts[:open].zero?

      Accounting::Notify.call(user: user, event: "digest:#{Date.current.iso8601}", subject: user, data: counts.stringify_keys).present?
    end
  end
end
