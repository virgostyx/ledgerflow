# F08: a remark of a thread is settled, or opened again; who and when are kept.
class Accounting::ResolveComment
  def self.call(comment:, user:, resolved: true)
    ctx = LightService::Context.make(comment: comment)
    return ctx.tap { |c| c.fail!(I18n.t("errors.not_authorized")) } unless Accounting::CommentPolicy.new(user, comment).resolve?

    comment.update!(resolved_at: (Time.current if resolved), resolved_by: (user if resolved))
    ctx
  end
end
