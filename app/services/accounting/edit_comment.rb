# F08: the author changes a comment, for fifteen minutes after writing it; never once it is hidden. A person named for the first time is told, one
# already told is not told again.
class Accounting::EditComment
  def self.call(comment:, user:, body:)
    ctx = LightService::Context.make(comment: comment)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.tasks.errors.comment_locked")) } unless Accounting::CommentPolicy.new(user, comment).edit?
    return ctx.tap { |c| c.fail!(I18n.t("activerecord.errors.messages.blank")) } if body.to_s.strip.blank?

    mentioned, = Accounting::AddComment.send(:resolve_mentions, body.strip, comment.commentable, user)
    comment.update!(body: body.strip, edited_at: Time.current, mentioned_user_ids: (comment.mentioned_user_ids + mentioned.map(&:id)).uniq)
    mentioned.each { |person| Accounting::Notify.call(user: person, event: "mention", subject: comment, data: { by: user.full_name }) }
    ctx
  end
end
