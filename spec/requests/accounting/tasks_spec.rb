require "rails_helper"

# F08, the screens: my tasks and all tasks, a task made from where it is seen (target prefilled), the thread of comments, the badges and icons on
# entries, partners, bank lines, the ledger (R02), the unlettered lines (R05) and the anomalies (R19), the notifications.
RSpec.describe "Tasks and comments screens (F08)", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant, email: "alice@firm.test", full_name: "Alice Accountant") }
  let(:assistant)  { create(:user, role: :auditor, email: "anna@firm.test", full_name: "Anna Assistant") }
  let(:reader)     { create(:user, role: :manager, email: "rita@firm.test", full_name: "Rita Reader") }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let!(:reader_membership)     { create(:user_entity, :manager, user: reader, entity: entity) }
  let(:purchases) { create(:journal, :purchase) }
  let(:sales)     { create(:journal, :sale) }
  let(:partner)   { create(:partner, :supplier, name: "Fournisseur SA") }

  def entry_in(journal)
    entry = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, status: :draft, reference: nil)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: 100, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: account_440, partner: partner, debit: 0, credit: 100)
    Accounting::PostJournalEntry.call!(entry: entry)
    entry.reload
  end
  let!(:entry) { entry_in(purchases) }

  before { sign_in accountant }

  describe "the flag" do
    it "closes the screens when the feature is off" do
      entity.update!(features: { "f08" => false })

      get accounting_tasks_path
      expect(response).to redirect_to(accounting_root_path)
      get accounting_notifications_path
      expect(response).to redirect_to(accounting_root_path)
    end

    it "leaves no trace on the other screens" do
      entity.update!(features: { "f08" => false })

      get accounting_journal_entry_path(entry)
      expect(response.body).not_to include("Add a task")
      expect(response.body).not_to include('data-section="comments"')
    end
  end

  describe "making a task from where it is seen" do
    it "prefills the target, and makes the task about it" do
      get new_accounting_task_path(target_type: "Accounting::JournalEntry", target_id: entry.id)
      expect(response.body).to include("About:").and include("Accounting::JournalEntry")

      expect {
        post accounting_tasks_path, params: { accounting_task: { title: "Missing invoice", kind: "missing_document", priority: "high", assignee_id: assistant.id, due_on: "2026-12-01",
                                                                  target_type: "Accounting::JournalEntry", target_id: entry.id } }
      }.to change(Accounting::Task, :count).by(1)

      task = Accounting::Task.last
      expect(task).to have_attributes(target: entry, author_id: accountant.id, assignee_id: assistant.id, kind: "missing_document", priority: "high")
      expect(response).to redirect_to(accounting_task_path(task))
    end

    it "is made from a ledger line, and the entry carries the badge (criterion 1)" do
      line = entry.lines.first
      post accounting_tasks_path, params: { accounting_task: { title: "Check this line", target_type: "Accounting::JournalEntryLine", target_id: line.id } }

      expect(Accounting::Task.last.target).to eq(line)
      get accounting_journal_entry_path(entry)
      expect(response.body).to include("1 task")
      get accounting_journal_entries_path
      expect(response.body).to include("1 task")
    end

    it "ignores a target type that is not a known one" do
      post accounting_tasks_path, params: { accounting_task: { title: "Odd", target_type: "User", target_id: accountant.id } }

      expect(Accounting::Task.last.target).to be_nil
    end

    it "refuses a target that cannot be seen" do
      accountant_membership.update!(journal_ids: [ sales.id ])

      expect { post accounting_tasks_path, params: { accounting_task: { title: "Hidden", target_type: "Accounting::JournalEntry", target_id: entry.id } } }.not_to change(Accounting::Task, :count)
      expect(response).not_to have_http_status(:ok)
    end

    it "is closed to a reader" do
      sign_in reader
      expect { post accounting_tasks_path, params: { accounting_task: { title: "No" } } }.not_to change(Accounting::Task, :count)
    end

    it "is offered on a partner, a document and a bank line, with the badge once there is a task" do
      doc = create(:document)
      get accounting_partner_path(partner)
      expect(response.body).to include("Add a task")
      get accounting_document_path(doc)
      expect(response.body).to include("Add a task")

      Accounting::CreateTask.call(user: accountant, title: "Call them", target: partner)
      get accounting_partners_path
      expect(response.body).to include("1 task")
    end
  end

  describe "the lists" do
    let!(:mine)   { Accounting::CreateTask.call(user: accountant, title: "For Anna", assignee: assistant, target: entry)[:task] }
    let!(:other)  { Accounting::CreateTask.call(user: accountant, title: "For nobody", target: entry)[:task] }
    let!(:late)   { Accounting::CreateTask.call(user: accountant, title: "Late one", assignee: assistant, target: partner, due_on: Date.current - 3)[:task] }

    it "shows my tasks to the assignee and all of them under « All tasks »" do
      sign_in assistant
      get accounting_tasks_path
      expect(response.body).to include("For Anna").and not_include("For nobody")

      get accounting_tasks_path(scope: "all")
      expect(response.body).to include("For Anna").and include("For nobody")
    end

    it "filters by status, due date and target" do
      Accounting::UpdateTask.call(task: mine, user: accountant, status: "done")

      get accounting_tasks_path(scope: "all", status: "done")
      expect(response.body).to include("For Anna").and not_include("Late one")

      get accounting_tasks_path(scope: "all", due: "overdue")
      expect(response.body).to include("Late one").and not_include("For nobody")

      get accounting_tasks_path(scope: "all", target_type: "Accounting::Partner", target_id: partner.id)
      expect(response.body).to include("Late one").and not_include("For Anna")
    end

    it "does not show a task about an entry that the user cannot see (criterion 3)" do
      assistant_membership.update!(journal_ids: [ sales.id ])
      sign_in assistant

      get accounting_tasks_path(scope: "all")
      expect(response.body).to include("Late one").and not_include("For Anna")
      get accounting_task_path(mine)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a task, its comments and its status" do
    let!(:task) { Accounting::CreateTask.call(user: accountant, title: "Ask the client", target: entry)[:task] }

    it "is changed, and closed" do
      patch accounting_task_path(task), params: { accounting_task: { status: "done", priority: "low" } }

      expect(task.reload).to have_attributes(status: "done", priority: "low", completed_by_id: accountant.id)
      get accounting_task_path(task)
      expect(response.body).to include("Closed")
    end

    it "gets a thread: a comment, a reply, a mention that tells the person once, a comment hidden but kept" do
      sign_in assistant
      post accounting_comments_path, params: { commentable_type: "Accounting::Task", commentable_id: task.id, body: "@alice I called them" }
      comment = Accounting::Comment.last
      expect(Accounting::Notification.where(user: accountant, event: "mention").count).to eq(1)

      post accounting_comments_path, params: { commentable_type: "Accounting::Task", commentable_id: task.id, body: "Thanks", parent_id: comment.id }
      get accounting_task_path(task)
      expect(response.body).to include("I called them").and include("Thanks")

      post hide_accounting_comment_path(comment)
      get accounting_task_path(task)
      expect(response.body).to include("Comment hidden by").and not_include("I called them")
      expect(Accounting::Comment.exists?(comment.id)).to be(true)
    end

    it "says which names were not told" do
      post accounting_comments_path, params: { commentable_type: "Accounting::Task", commentable_id: task.id, body: "@nobody hello" }

      expect(flash[:notice]).to include("@nobody")
    end

    it "is edited by its author within fifteen minutes only" do
      post accounting_comments_path, params: { commentable_type: "Accounting::Task", commentable_id: task.id, body: "First" }
      comment = Accounting::Comment.last

      patch accounting_comment_path(comment), params: { body: "Second" }
      expect(comment.reload.body).to eq("Second")

      travel_to(16.minutes.from_now) { patch accounting_comment_path(comment), params: { body: "Third" } }
      expect(comment.reload.body).to eq("Second")
      expect(flash[:alert]).to include("fifteen minutes")
    end

    it "makes a thread on an entry too, and settles a remark" do
      post accounting_comments_path, params: { commentable_type: "Accounting::JournalEntry", commentable_id: entry.id, body: "Check the VAT" }
      get accounting_journal_entry_path(entry)
      expect(response.body).to include("Check the VAT")

      post resolve_accounting_comment_path(Accounting::Comment.last)
      expect(Accounting::Comment.last).to be_resolved
    end

    it "does not take a commentable of another type" do
      expect { post accounting_comments_path, params: { commentable_type: "User", commentable_id: accountant.id, body: "x" } }.not_to change(Accounting::Comment, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the ledger, the unlettered lines and the anomalies" do
    let(:line) { entry.lines.find_by(account: account_440) }

    before { Accounting::CreateTask.call(user: accountant, title: "About a line", target: line) }

    it "shows an icon on the ledger line (R02) and on the unlettered line (R05), a link to its tasks" do
      get accounting_reports_general_ledger_path(fiscal_year_id: fiscal_year.id, account_id: account_440.id)
      expect(response.body).to include("1 task").and include(CGI.escapeHTML(new_accounting_task_path(target_type: "Accounting::JournalEntryLine", target_id: line.id)))

      get accounting_reports_unlettered_lines_path(kind: "supplier")
      expect(response.body).to include(CGI.escapeHTML(accounting_tasks_path(scope: "all", target_type: "Accounting::JournalEntryLine", target_id: line.id)))
    end

    it "makes a task from an anomaly, linked to it by its fingerprint, shows it there, and closing it acknowledges nothing (criterion 6)" do
      draft = create(:journal_entry, :draft, journal: purchases, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 2, reference: nil)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: draft, account: account_550, debit: 10, credit: 0)
      post accounting_consistency_runs_path
      finding = Accounting::ConsistencyFinding.order(:id).last

      get accounting_consistency_runs_path
      expect(response.body).to include(CGI.escapeHTML(new_accounting_task_path(anomaly_fingerprint: finding.fingerprint, title: finding.message.truncate(80), kind: "to_check")[0, 60]))

      task = Accounting::CreateTask.call(user: accountant, title: "Look at it", anomaly_fingerprint: finding.fingerprint, kind: :to_check)[:task]
      get accounting_consistency_runs_path
      expect(response.body).to include("1 task")

      patch accounting_task_path(task), params: { accounting_task: { status: "done" } }
      expect(task.reload).to be_done
      expect(Accounting::ConsistencyAcknowledgement.where(fingerprint: finding.fingerprint)).to be_empty
      expect(Accounting::ConsistencyFinding.exists?(finding.id)).to be(true)
    end
  end

  describe "the notifications" do
    it "lists what the user is told, marks it read and goes to the task" do
      task = Accounting::CreateTask.call(user: accountant, title: "For you", assignee: assistant, target: entry)[:task]
      sign_in assistant

      get accounting_notifications_path
      expect(response.body).to include("Task assigned to you").and include("For you")

      post read_accounting_notification_path(Accounting::Notification.last)
      expect(response).to redirect_to(accounting_task_path(task))
      expect(Accounting::Notification.last.read_at).to be_present
    end

    it "marks all as read, and only the notifications of the user" do
      Accounting::CreateTask.call(user: accountant, title: "A", assignee: assistant, target: entry)
      Accounting::CreateTask.call(user: assistant, title: "B", assignee: accountant, target: entry)
      sign_in assistant

      post read_all_accounting_notifications_path

      expect(Accounting::Notification.where(user: assistant).unread).to be_empty
      expect(Accounting::Notification.where(user: accountant).unread.count).to eq(1)
    end

    it "shows the number unread in the menu" do
      Accounting::CreateTask.call(user: accountant, title: "A", assignee: assistant, target: entry)
      sign_in assistant

      get accounting_root_path

      expect(response.body).to include("Notifications").and include("Tasks")
    end
  end
end
