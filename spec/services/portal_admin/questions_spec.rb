require 'rails_helper'

# B02c, "Questions au client": the firm asks, the client answers by type, the answer becomes a comment of the F08 task and tells the firm; a quick choice shows a suggestion and applies nothing.
RSpec.describe 'Questions to the client' do
  include_context 'with entity'

  let(:staff)  { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:person) { create(:portal_user, full_name: 'Jane Client') }
  let!(:line)  { create(:bank_transaction, counterparty_name: 'ACME Supplies', amount: BigDecimal('-80.00'), transaction_date: Date.new(2026, 3, 4)) }

  before do
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: 'director', capabilities: %w[questions.answer documents.upload])
    ActionMailer::Base.deliveries.clear
  end

  def ask(**overrides)
    PortalAdmin::AskQuestion.call(entity: entity, by: staff, title: 'Is this expense professional?', answer_type: 'single', target: line, due_on: Date.new(2026, 4, 1),
                                  choices: [ { key: 'yes', label: 'Yes', suggested_treatment: 'professional: book as an expense' }, { key: 'no', label: 'No', suggested_treatment: 'private: book to the current account' } ], **overrides)
  end

  describe PortalAdmin::AskQuestion do
    it 'opens a task of the firm and a question for the client, with the limited context of the line' do
      result = ask

      expect(result).to be_success
      question = Portal::Question.sole
      expect(question).to have_attributes(status: 'open', answer_type: 'single', title: 'Is this expense professional?', task_id: result[:task].id)
      expect(question.context).to include('date' => '2026-03-04', 'label' => 'ACME Supplies', 'amount' => '-80.0')
      expect(question.choices).to eq([ { 'key' => 'yes', 'label' => 'Yes' }, { 'key' => 'no', 'label' => 'No' } ]) # no suggestion in what the client can read
      expect(result[:task]).to have_attributes(kind: 'client_question', target: line)
    end

    it 'keeps the suggestions on the firm side only' do
      ask
      expect(Portal::Question.sole.attributes.values.join(' ')).not_to include('book as an expense')
      expect(Accounting::QuestionSuggestion.pluck(:choice_key, :treatment)).to contain_exactly([ 'yes', 'professional: book as an expense' ], [ 'no', 'private: book to the current account' ])
    end

    it 'tells the people who may answer, with a count and no content' do
      ask
      mail = ActionMailer::Base.deliveries.sole
      expect(mail.to).to eq([ person.email ])
      expect(mail.body.to_s).not_to include('expense', 'ACME')
    end

    it 'refuses a type it does not know, a choice question without choices, and an empty title' do
      expect(ask(answer_type: 'poem')).to be_failure
      expect(ask(choices: [])).to be_failure
      expect(ask(title: ' ')).to be_failure
      expect(Portal::Question.count).to eq(0)
    end

    it 'refuses when the company turned the feature off, or when nobody can answer' do
      entity.update!(features: { 'b02c' => false })
      expect(ask).to be_failure
      entity.update!(features: { 'b02c' => true })
      person.grants.destroy_all
      expect(ask).to be_failure
    end

    it 'needs no choices for a free text, a yes or no, a file, an amount or a date' do
      %w[text yes_no file amount date].each { |type| expect(ask(answer_type: type, choices: [])).to be_success }
    end
  end

  describe PortalAdmin::SyncAnswers do
    let(:question) { ask[:question] }

    def answer!(value: { 'choices' => [ 'yes' ] }, body: nil)
      Portal::Answer.create!(question: question, portal_user: person, entity_id: entity.id, value: value, body: body, answered_at: Time.current)
      question.update!(status: 'answered')
    end

    it 'turns an answer into a comment of the task, and tells the author, once' do
      answer!(body: 'It was a client lunch')
      ActionMailer::Base.deliveries.clear

      described_class.call
      described_class.call

      task = Accounting::Task.find(question.task_id)
      comment = task.comments.sole
      expect(comment).to have_attributes(external_name: 'Jane Client', author_id: nil)
      expect(comment.body).to include('Yes', 'It was a client lunch')
      expect(Accounting::Notification.where(user: staff, event: 'external_reply').count).to eq(1)
      expect(Accounting::AuditLog.where(action: 'portal_question_answered').count).to eq(1)
    end

    it 'shows the suggestion of the choice to the accountant, as a suggestion, and applies nothing' do
      answer!

      expect { described_class.call }.not_to change { [ Accounting::JournalEntry.count, Accounting::BankTransaction.find(line.id).attributes ] }

      body = Accounting::Task.find(question.task_id).comments.sole.body
      expect(body).to include('Suggestion (not applied): professional: book as an expense')
    end

    it 'waits for the files sent with the answer to be taken in, then says what was kept' do
      answer!
      upload = Portal::Upload.create!(entity_id: entity.id, portal_user: person, filename: 'invoice.pdf', byte_size: 1, sha256: 'a' * 64, chunk_size: 1, chunk_count: 1, status: 'received',
                                      question_id: question.id, expires_at: 1.day.from_now)

      described_class.call
      expect(Accounting::Task.find(question.task_id).comments).to be_empty

      upload.update!(status: 'accepted')
      described_class.call
      expect(Accounting::Task.find(question.task_id).comments.sole.body).to include('Files sent (in the document inbox): invoice.pdf')
    end

    it 'flags to the team an answer about something whose period is closed, and still changes nothing' do
      create(:fiscal_year, year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), status: :closed)
      answer!

      expect { described_class.call }.not_to change(Accounting::JournalEntry, :count)

      expect(Accounting::Task.find(question.task_id).comments.sole.body).to include('The period of this thing is closed')
    end

    it 'does not touch the books, even when the period is closed' do
      answer!
      expect { described_class.call }.not_to change(Accounting::JournalEntry, :count)
    end
  end
end

RSpec.describe PortalAdmin::RemindQuestions do
  include_context 'with entity'

  let(:staff)  { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:person) { create(:portal_user) }
  let(:asked_at) { Time.zone.local(2026, 5, 4, 10, 0) } # a Monday morning

  before do
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: 'director', capabilities: %w[questions.answer])
    ActionMailer::Base.deliveries.clear
  end

  def ask(title = 'A question')
    travel_to(asked_at) { PortalAdmin::AskQuestion.call(entity: entity, by: staff, title: title, answer_type: 'text')[:question] }.tap { ActionMailer::Base.deliveries.clear }
  end

  def remind_at(time) = travel_to(time) { described_class.call }

  it 'reminds on day 3, 7 and 14, and not before' do
    question = ask
    remind_at(asked_at + 2.days)
    expect(ActionMailer::Base.deliveries).to be_empty

    remind_at(asked_at + 3.days)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    remind_at(asked_at + 3.days + 1.hour)
    expect(ActionMailer::Base.deliveries.size).to eq(1) # once

    remind_at(asked_at + 7.days)
    remind_at(asked_at + 14.days)
    expect(question.reload.reminders_sent).to eq(3)
  end

  it 'groups the questions of a person in one message with a count' do
    5.times { |i| ask("Question #{i}") }
    remind_at(asked_at + 3.days)

    mail = ActionMailer::Base.deliveries.sole
    expect(mail.subject).to include('5 questions')
    expect(mail.body.to_s).not_to include('Question 0')
  end

  it 'stops at the answer' do
    question = ask
    Portal::Answer.create!(question: question, portal_user: person, entity_id: entity.id, answered_at: Time.current)
    question.update!(status: 'answered')

    remind_at(asked_at + 3.days)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'sends at most two reminders a week to a person' do
    one = ask('One')
    two = travel_to(asked_at + 1.day) { PortalAdmin::AskQuestion.call(entity: entity, by: staff, title: 'Two', answer_type: 'text')[:question] }
    three = travel_to(asked_at + 2.days) { PortalAdmin::AskQuestion.call(entity: entity, by: staff, title: 'Three', answer_type: 'text')[:question] }
    ActionMailer::Base.deliveries.clear

    remind_at(asked_at + 3.days) # day 3 of the first
    remind_at(asked_at + 4.days) # day 3 of the second
    expect(ActionMailer::Base.deliveries.size).to eq(2)
    remind_at(asked_at + 5.days) # day 3 of the third: the week is full
    expect(ActionMailer::Base.deliveries.size).to eq(2)
    expect(three.reload.reminders_sent).to eq(0)

    remind_at(asked_at + 11.days) # the week has moved on: one message for what is due
    expect(ActionMailer::Base.deliveries.size).to eq(3)
    expect([ one, two, three ].map { |q| q.reload.reminders_sent }).to eq([ 2, 2, 1 ])
  end

  it 'keeps quiet at night in Brussels time, and tries again in the morning' do
    question = ask
    remind_at(asked_at + 3.days + 9.hours) # 19:00 UTC is 21:00 in Brussels (summer)
    expect(ActionMailer::Base.deliveries).to be_empty
    remind_at(asked_at + 4.days - 4.hours) # 06:00 UTC is 08:00 in Brussels: quiet no more
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(question.reload.reminders_sent).to eq(1)
  end

  it 'makes a follow-up task for the firm when day 14 passes without an answer, once' do
    question = ask('Nobody answers')
    [ 3, 7, 14, 15 ].each { |d| remind_at(asked_at + d.days) }

    tasks = Accounting::Task.where("title LIKE ?", 'No answer from the client%')
    expect(tasks.count).to eq(1)
    expect(tasks.first.title).to include('Nobody answers')
    expect(tasks.first.assignee_id).to eq(question.asked_by_id)
  end

  it 'says nothing to someone who chose not to be told, but still makes the follow-up' do
    person.update!(notification_frequency: 'off')
    ask
    [ 3, 7, 14 ].each { |d| remind_at(asked_at + d.days) }
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(Accounting::Task.where("title LIKE ?", 'No answer from the client%').count).to eq(1)
  end
end
