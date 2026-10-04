# F08: ends the link of a third party at once (the question is kept).
class Accounting::RevokeExternalLink
  def self.call(task:, user:)
    ctx = LightService::Context.make(task: task)
    return ctx.tap { |c| c.fail!(I18n.t("errors.not_authorized")) } unless Accounting::TaskPolicy.new(user, task).update?

    ApplicationRecord.transaction do
      task.update!(external_expires_at: nil)
      Accounting::AuditLog.record!(auditable: task, action: "task_external_link_revoked", user: user)
    end
    ctx
  end
end
