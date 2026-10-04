# F08: a comment is never deleted: it is hidden (its text is no longer shown), by its author or by whoever manages tasks, and the audit trail says who.
class Accounting::HideComment
  def self.call(comment:, user:)
    ctx = LightService::Context.make(comment: comment)
    return ctx.tap { |c| c.fail!(I18n.t("errors.not_authorized")) } unless Accounting::CommentPolicy.new(user, comment).hide?
    return ctx if comment.hidden?

    ApplicationRecord.transaction do
      comment.update!(hidden_at: Time.current, hidden_by: user)
      Accounting::AuditLog.record!(auditable: comment, action: "comment_hidden", user: user, payload: { commentable_type: comment.commentable_type, commentable_id: comment.commentable_id })
    end
    ctx
  end
end
