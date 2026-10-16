# B02c: the firm asks the people of a company's portal a question about an entry, a bank line or a document. A task of the firm (F08, kind client_question) holds it; the client reads a title,
# the limited context (date, cleaned label, amount; a document's name) and the choices. The treatments suggested per choice stay on the firm's side. The people who may answer are told that
# there is a question, not which.
class PortalAdmin::AskQuestion
  def self.call(entity:, **args) = ActsAsTenant.with_tenant(entity) { perform(entity: entity, **args) }

  def self.perform(entity:, by:, title:, answer_type:, target: nil, choices: [], due_on: nil, person: nil)
    context = LightService::Context.make(question: nil, task: nil)
    return fail_with(context, "The client questions are not turned on for this company.") unless entity.feature?(:b02a) && entity.feature?(:b02c) && entity.feature?(:f08)
    return fail_with(context, "Write the question.") if title.to_s.strip.blank?
    return fail_with(context, "Choose a type of answer.") unless Portal::Question::ANSWER_TYPES.include?(answer_type.to_s)

    choices = Array(choices).map { |c| c.to_h.symbolize_keys }.select { |c| c[:key].present? && c[:label].present? }
    return fail_with(context, "A question with choices needs at least two.") if Portal::Question::CHOICE_TYPES.include?(answer_type.to_s) && choices.size < 2

    recipients = people(entity, person)
    return fail_with(context, "Nobody of the client portal may answer questions yet.") if recipients.empty?

    task = Accounting::CreateTask.call(user: by, title: title.to_s.strip.first(200), kind: :client_question, target: target, due_on: due_on.presence)
    return fail_with(context, task.message) if task.failure?

    question = ApplicationRecord.transaction do
      Portal::Question.create!(entity_id: entity.id, task_id: task[:task].id, portal_user: person, title: title.to_s.strip.first(200), context: context_of(target), answer_type: answer_type.to_s,
                               choices: choices.map { |c| { "key" => c[:key].to_s, "label" => c[:label].to_s.first(200) } }, due_on: due_on.presence, asked_at: Time.current, asked_by_id: by.id).tap do |created|
        choices.each { |c| Accounting::QuestionSuggestion.create!(entity_id: entity.id, portal_question_id: created.id, choice_key: c[:key].to_s, treatment: c[:suggested_treatment].to_s.first(300)) if c[:suggested_treatment].present? }
        Accounting::AuditLog.record!(auditable: task[:task], action: "portal_question_asked", user: by, payload: { question: created.token, answer_type: answer_type.to_s })
      end
    end
    recipients.each { |p| notify(p, entity) }
    context[:question] = question
    context[:task] = task[:task]
    context
  end

  # Whoever may answer: active, with a right in force listing questions.answer; or the one person the question is addressed to.
  def self.people(entity, person = nil)
    granted = Portal::Grant.in_force.where(entity_id: entity.id).where("capabilities @> ?", [ "questions.answer" ].to_json).select(:portal_user_id)
    people = PortalUser.active.where(id: granted)
    person ? people.where(id: person.id).to_a : people.to_a
  end

  # The thing asked about, as far as the client may see it. Never an IBAN, never a bank reference.
  def self.context_of(target)
    case target
    when Accounting::BankTransaction then { "date" => target.transaction_date.iso8601, "label" => PortalAdmin::BankLineLabel.call(target), "amount" => target.amount.to_s("F").sub(/(\.\d)\z/, '\1'), "currency" => target.currency }
    when Accounting::Document then { "document" => target.name }
    when Accounting::JournalEntry then { "date" => target.entry_date.iso8601, "reference" => target.reference }.compact
    else {}
    end
  end

  def self.notify(person, entity)
    return if person.notification_frequency == "off"

    Portal::NotificationMailer.questions_waiting(person, entity.name, 1).deliver_now
  rescue StandardError => e
    Rails.logger.error("portal notification not sent: #{e.class}")
  end

  def self.fail_with(context, message) = context.tap { |c| c.fail!(message) }
  private_class_method :perform, :context_of, :notify, :fail_with
end
