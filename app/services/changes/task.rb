# B03b: a task (F08) about a change of the report, the thing it is about prefilled when a task can be about it. The key is the one of `Changes::Key` ("entry:<id>" for an entry).
module Changes::Task
  EVENT_KEY = /\A(?<category>\w+):(?<type>[\w:]+):(?<id>\d+):(?<action>\w+):(?<at>[\dT:.\-Z]+)\z/

  def self.call(key:, user:)
    target, text = resolve(key.to_s)
    return fail_with(I18n.t("changes.errors.unknown_change")) unless text

    Accounting::CreateTask.call(user: user, title: I18n.t("changes.task_title", what: text), description: I18n.t("changes.task_description", key: key), kind: :to_check, target: target)
  end

  def self.resolve(key)
    if (id = key[/\Aentry:(\d+)\z/, 1])
      entry = Accounting::JournalEntry.find_by(id: id) or return
      [ entry, entry.reference.presence || "##{entry.id}" ]
    elsif (match = EVENT_KEY.match(key))
      type = match[:type]
      target = (Accounting::TaskTargets::TYPES.include?(type) && type.constantize.find_by(id: match[:id])) || nil
      [ target, "#{match[:action].tr('_', ' ')} (#{match[:category]})" ]
    end
  end
  private_class_method :resolve

  def self.fail_with(message) = LightService::Context.make(task: nil).tap { |c| c.fail!(message) }
  private_class_method :fail_with
end
