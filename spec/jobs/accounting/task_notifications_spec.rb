require "rails_helper"

# F08, notifications: in the application and by e-mail (when asked for), a reminder the day before a task is due, a daily summary, each told once.
RSpec.describe "Task notifications (F08)" do
  include_context "with_open_fiscal_year"
  include ActiveJob::TestHelper

  let(:accountant) { create(:user, role: :accountant, email: "alice@firm.test", full_name: "Alice Accountant") }
  let(:assistant)  { create(:user, role: :auditor, email: "anna@firm.test", full_name: "Anna Assistant") }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  def task(title = "T", **attrs) = Accounting::CreateTask.call(user: accountant, title: title, **attrs)[:task]

  describe "e-mails" do
    it "tells the assignee by e-mail as well as in the application" do
      expect { task(assignee: assistant) }.to have_enqueued_mail(Accounting::TaskMailer, :task_assigned)
      expect(Accounting::Notification.where(user: assistant, channel: :in_app).count).to eq(1)
    end

    it "does not e-mail a person who turned e-mails off, but lists the notification" do
      assistant_membership.update!(notify_by_email: false)

      expect { task(assignee: assistant) }.not_to have_enqueued_mail(Accounting::TaskMailer)
      expect(Accounting::Notification.where(user: assistant).count).to eq(1)
    end

    it "says what the mail is about: the task, who did it, and the comment of a mention" do
      t = task("Missing invoice", assignee: assistant, due_on: Date.new(2026, 12, 1))
      mail = Accounting::TaskMailer.task_assigned(Accounting::Notification.find_by!(user: assistant, event: "task_assigned"))
      expect(mail.to).to eq([ "anna@firm.test" ])
      expect(mail.subject).to include("assigned to you")
      expect(mail.body.encoded).to include("Missing invoice").and include("Alice Accountant")

      comment = Accounting::AddComment.call(commentable: t, user: accountant, body: "@anna please check")[:comment]
      mention = Accounting::TaskMailer.mention(Accounting::Notification.find_by!(user: assistant, event: "mention", subject: comment))
      expect(mention.body.encoded).to include("please check")
    end

    it "does not e-mail a mention twice" do
      t = task
      comment = Accounting::AddComment.call(commentable: t, user: accountant, body: "@anna look")[:comment]
      Accounting::EditComment.call(comment: comment, user: accountant, body: "@anna look again")

      expect(Accounting::Notification.where(user: assistant, event: "mention").count).to eq(1)
    end
  end

  describe Accounting::TaskDueRemindersJob do
    it "reminds the assignee of an open task due tomorrow, once" do
      due = task("Due soon", assignee: assistant, due_on: Date.current + 1)
      clear_enqueued_jobs

      expect(described_class.perform_now).to eq(1)
      expect(described_class.perform_now).to eq(0)
      expect(Accounting::Notification.where(user: assistant, event: "task_due:#{due.due_on.iso8601}").count).to eq(1)
      expect(Accounting::TaskMailer).to have_been_enqueued if false
    end

    it "e-mails the reminder, and reminds again when the due date moves" do
      due = task("Moves", assignee: assistant, due_on: Date.current + 1)
      clear_enqueued_jobs

      expect { described_class.perform_now }.to have_enqueued_mail(Accounting::TaskMailer, :task_due)

      Accounting::UpdateTask.call(task: due, user: accountant, due_on: Date.current + 3)
      travel_to(2.days.from_now) { expect(described_class.perform_now).to eq(1) }
    end

    it "leaves out a task that is closed, with nobody assigned, or not due tomorrow" do
      done = task("Done", assignee: assistant, due_on: Date.current + 1)
      Accounting::UpdateTask.call(task: done, user: accountant, status: "done")
      task("Nobody", due_on: Date.current + 1)
      task("Later", assignee: assistant, due_on: Date.current + 2)

      expect(described_class.perform_now).to eq(0)
    end

    it "works for every entity, each in its own" do
      other = create(:entity)
      ActsAsTenant.with_tenant(other) do
        create(:user_entity, :accountant, user: accountant, entity: other)
        Accounting::Task.create!(title: "Elsewhere", assignee: accountant, due_on: Date.current + 1)
      end
      task("Here", assignee: assistant, due_on: Date.current + 1)

      expect(described_class.perform_now).to eq(2)
    end
  end

  describe Accounting::DailyTaskDigestJob do
    before { assistant_membership.update!(notify_daily_digest: true) }

    it "sends one summary to the person who asked for it, with the numbers of their open, overdue and soon-due tasks" do
      task("Late", assignee: assistant, due_on: Date.current - 2)
      task("Soon", assignee: assistant, due_on: Date.current + 2)
      task("No date", assignee: assistant)
      clear_enqueued_jobs

      expect { expect(described_class.perform_now).to eq(1) }.to have_enqueued_mail(Accounting::TaskMailer, :digest)

      digest = Accounting::Notification.find_by!(user: assistant, subject_type: "User")
      expect(digest.data).to include("open" => 3, "overdue" => 1, "soon" => 1)
      body = Accounting::TaskMailer.digest(digest).body.encoded
      expect(body).to include("3 open task(s)").and include("1 overdue")
    end

    it "sends it once a day, and again the next day" do
      task("A", assignee: assistant)

      expect(described_class.perform_now).to eq(1)
      expect(described_class.perform_now).to eq(0)
      travel_to(1.day.from_now) { expect(described_class.perform_now).to eq(1) }
    end

    it "sends nothing to a person who did not ask, or who has no open task" do
      task("Mine", assignee: accountant)
      expect(described_class.perform_now).to eq(0)

      accountant_membership.update!(notify_daily_digest: true)
      assistant_membership.update!(notify_daily_digest: true)
      expect(described_class.perform_now).to eq(1) # the accountant, who has one; the assistant has none
    end

    it "counts only the tasks the person may see" do
      sales = create(:journal, :sale)
      purchases = create(:journal, :purchase)
      entry = create(:journal_entry, journal: purchases, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 1, reference: "P1")
      task("Hidden", assignee: assistant, target: entry)
      assistant_membership.update!(journal_ids: [ sales.id ])

      expect(described_class.perform_now).to eq(0)
    end
  end
end
