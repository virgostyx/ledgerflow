# F08: a comment in the thread of a task or of a thing, by someone who may comment on it. The people it names with @ (the part of the e-mail before
# the @, among the members of the entity) are told once, if they may see what it is about; a name that is unknown, ambiguous or that sees nothing
# is not a mention and is listed in ctx[:ignored_mentions]. Commenting changes nothing in what is commented.
class Accounting::AddComment
  HANDLE = /(?<![\w@.])@([a-z0-9][a-z0-9._-]*[a-z0-9]|[a-z0-9])/i

  def self.call(commentable:, user:, body:, parent: nil)
    ctx = LightService::Context.make(comment: nil, ignored_mentions: [])
    comment = Accounting::Comment.new(commentable: commentable, author: user, body: body.to_s.strip, parent: parent)
    return ctx.tap { |c| c.fail!(I18n.t("errors.not_authorized")) } unless Accounting::CommentPolicy.new(user, comment).create?
    return ctx.tap { |c| c.fail!(I18n.t("accounting.tasks.errors.reply_to_other_thread")) } if parent && parent.commentable != commentable

    mentioned, ignored = resolve_mentions(comment.body, commentable, user)
    comment.mentioned_user_ids = mentioned.map(&:id)
    return ctx.tap { |c| c.fail!(comment.errors.full_messages.to_sentence) } unless comment.save

    mentioned.each { |person| Accounting::Notify.call(user: person, event: "mention", subject: comment, data: { by: user.full_name }) }
    ctx[:comment] = comment
    ctx[:ignored_mentions] = ignored
    ctx
  end

  # => [the users named who may see what is commented, the names that mention nobody]
  def self.resolve_mentions(body, target, author)
    handles = body.scan(HANDLE).flatten.map(&:downcase).uniq
    return [ [], [] ] if handles.empty?

    members = User.where(id: UserEntity.current.where(entity_id: ActsAsTenant.current_tenant.id).select(:user_id)).to_a.group_by { |u| u.email.split("@").first.downcase }
    found = []
    ignored = []
    handles.each do |handle|
      people = members.fetch(handle, [])
      person = people.first if people.one?
      if person && person != author && Accounting::TaskTargets.visible_commentable?(person, target)
        found << person
      else
        ignored << handle
      end
    end
    [ found, ignored ]
  end
  private_class_method :resolve_mentions
end
