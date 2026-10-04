# F08: what a third party answers through the link of a task: a text, from a name they give, and files. The answer becomes a comment with no author
# in the thread of the task; the files go to the document inbox (F03, origin "external_reply"), checked like any upload; the author and the assignee
# of the task are told. Only while the link answers; a file that is refused is told to the sender, the rest is kept.
# => ctx[:comment], ctx[:refused] (the file names with the reason)
class Accounting::ReceiveExternalReply
  MAX_FILES = 3
  MAX_BODY = 5_000

  def self.call(task:, name:, body:, files: [], ip: nil)
    ctx = LightService::Context.make(comment: nil, refused: [])
    return ctx.tap { |c| c.fail!(I18n.t("accounting.tasks.errors.link_expired")) } unless task.external_open?

    name = name.to_s.strip
    body = body.to_s.strip
    files = Array(files).first(MAX_FILES)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.tasks.errors.reply_needs_name")) } if name.blank?
    return ctx.tap { |c| c.fail!(I18n.t("accounting.tasks.errors.reply_empty")) } if body.blank? && files.empty?
    return ctx.tap { |c| c.fail!(I18n.t("accounting.tasks.errors.reply_too_long", max: MAX_BODY)) } if body.length > MAX_BODY

    kept, refused = store(task, name, files)
    text = [ body.presence, ("Files sent (in the document inbox): #{kept.join(', ')}" if kept.any?), ("Files not accepted: #{refused.map { |n, why| "#{n} (#{why})" }.join(', ')}" if refused.any?) ].compact.join("\n\n")
    comment = Accounting::Comment.create!(commentable: task, external_name: name.truncate(100), body: text)
    Accounting::AuditLog.record!(auditable: task, action: "task_external_reply", user: nil, ip_address: ip, payload: { name: name.truncate(100), files: kept.size })
    [ task.author, task.assignee ].compact.uniq.each { |person| Accounting::Notify.call(user: person, event: "external_reply", subject: comment, data: { by: name.truncate(100) }) }
    ctx[:comment] = comment
    ctx[:refused] = refused
    ctx
  end

  # => [the names kept, [[name, why]] refused]
  def self.store(task, name, files)
    kept = []
    refused = []
    files.each do |file|
      result = Accounting::UploadDocument.call(io: file.tempfile, filename: file.original_filename, user: nil, origin: :external_reply, kind: :other,
                                               details: { "task_id" => task.id, "external_name" => name.truncate(100) })
      result.success? ? kept << file.original_filename : refused << [ file.original_filename, result.message ]
    end
    [ kept, refused ]
  end
  private_class_method :store
end
