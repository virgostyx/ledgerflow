# B02c: what the clients answered becomes, on the firm's side, a comment in the thread of the task of the question (author: the person's name, never a user of the firm), and the people of the
# task are told. The suggestion of a quick choice is written there as a suggestion. Nothing in the books changes, whatever the period: an answer after the closing is recorded and flagged, with no
# accounting effect. Once per answer.
class PortalAdmin::SyncAnswers
  def self.call
    Portal::Answer.where(synced_at: nil).includes(:question, :portal_user).group_by(&:entity_id).each do |entity_id, answers|
      ActsAsTenant.with_tenant(Entity.find(entity_id)) { answers.each { |answer| sync(answer) unless sending?(answer) } }
    end
  end

  def self.sync(answer)
    question = answer.question
    task = Accounting::Task.find_by(id: question.task_id) or return
    name = answer.portal_user.full_name.to_s.first(100)
    ApplicationRecord.transaction do
      comment = Accounting::Comment.create!(commentable: task, external_name: name, body: render(answer, question))
      answer.update!(synced_at: Time.current)
      Accounting::AuditLog.record!(auditable: task, action: "portal_question_answered", actor_type: "portal_user", payload: { question: question.token, portal_user_id: answer.portal_user_id, answer_type: question.answer_type })
      [ task.author, task.assignee ].compact.uniq.each { |person| Accounting::Notify.call(user: person, event: "external_reply", subject: comment, data: { by: name }) }
    end
  end

  # The files sent with an answer are taken in first (quarantine, checks), so that the comment can say what was kept.
  def self.sending?(answer) = Portal::Upload.where(question_id: answer.question_id, status: %w[receiving received]).exists?

  def self.render(answer, question)
    value = answer.value
    lines = [ "Answer to: #{question.title}" ]
    lines << "Chosen: #{Array(value['choices']).map { |key| question.choice_label(key) || key }.join(', ')}" if value["choices"].present?
    lines << "Answer: #{value['yes_no'] ? 'Yes' : 'No'}" if value.key?("yes_no")
    lines << "Amount: #{value['amount']}" if value["amount"].present?
    lines << "Date: #{value['date']}" if value["date"].present?
    lines << answer.body if answer.body.present?
    files = Portal::Upload.where(question_id: question.id)
    kept = files.where(status: %w[accepted to_complete]).pluck(:filename)
    lines << "Files sent (in the document inbox): #{kept.join(', ')}" if kept.any?
    lines << "Files not accepted: #{files.refused.map { |f| "#{f.filename} (#{Portal::Upload::REFUSALS.fetch(f.refusal_reason.to_s, 'refused')})" }.join(', ')}" if files.refused.exists?
    suggestions = Accounting::QuestionSuggestion.where(portal_question_id: question.id, choice_key: Array(value["choices"])).pluck(:treatment)
    lines << "Suggestion (not applied): #{suggestions.join(' / ')}" if suggestions.any?
    lines.join("\n")
  end
  private_class_method :sync, :render, :sending?
end
