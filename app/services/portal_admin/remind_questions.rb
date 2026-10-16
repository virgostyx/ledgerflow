# B02c: the friendly reminders of the questions still open, on day 3, 7 and 14 after they were asked. One message per person with a count (not one per question), at most two a week per person,
# never at night (quiet hours), and they stop at the answer. When day 14 has gone by, a follow-up task is made for the firm, once. A person who chose not to be told gets no message, but the firm
# still hears of a question nobody answers.
class PortalAdmin::RemindQuestions
  AFTER_DAYS = [ 3, 7, 14 ].freeze
  WEEKLY_CAP = 2
  QUIET_FROM = 20 # hour: from 20:00 to 08:00 nothing is sent
  QUIET_UNTIL = 8

  def self.call(now: Time.current)
    return if now.hour >= QUIET_FROM || now.hour < QUIET_UNTIL

    due = Portal::Question.open.where(reminders_sent: 0...AFTER_DAYS.size).select { |q| now >= q.asked_at + AFTER_DAYS.fetch(q.reminders_sent).days }
    reminded = Hash.new { |hash, key| hash[key] = [] }
    due.each do |question|
      people_of(question).each { |person| reminded[person] << question }
    end
    reminded.each { |person, questions| remind(person, questions, now) }
    due.each { |question| follow_up(question, now) if question.reminders_sent >= AFTER_DAYS.size }
  end

  def self.people_of(question)
    PortalAdmin::AskQuestion.people(Entity.find(question.entity_id), question.portal_user)
  end

  def self.remind(person, questions, now)
    if person.notification_frequency != "off"
      return if Portal::Event.where(action: "question_reminder", portal_user_id: person.id, occurred_at: (now - 7.days)..).count >= WEEKLY_CAP

      send_mail(person, questions)
      Portal::Event.record!("question_reminder", user: person, count: questions.size)
    end
    questions.each { |question| question.update!(reminders_sent: question.reminders_sent + 1, last_reminded_at: now) }
  end

  def self.send_mail(person, questions)
    Portal::NotificationMailer.questions_waiting(person, Portal::Company.find(questions.first.entity_id).name, questions.size).deliver_now
  rescue StandardError => e
    Rails.logger.error("portal reminder not sent: #{e.class}")
  end

  # The firm hears of a question nobody answers: one task, made when the last reminder has gone.
  def self.follow_up(question, now)
    ActsAsTenant.with_tenant(Entity.find(question.entity_id)) do
      original = Accounting::Task.find_by(id: question.task_id)
      Accounting::Task.create!(title: "No answer from the client: #{question.title}".first(200), kind: :to_check, assignee_id: question.asked_by_id, target: original&.target, due_on: now.to_date,
                               description: "The client was reminded three times (day 3, 7 and 14) and has not answered.")
    end
  end
  private_class_method :people_of, :remind, :send_mail, :follow_up
end
