require "rails_helper"

# F08 §11: tasks and comments about what one can see: linked to their target, told to the right person once, seen like their target, a comment
# edited for fifteen minutes and never deleted, nothing changed in the thing commented.
RSpec.describe "Tasks and comments (F08)" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:owner)      { create(:user, role: :admin, email: "olivia@firm.test", full_name: "Olivia Owner") }
  let(:accountant) { create(:user, role: :accountant, email: "alice@firm.test", full_name: "Alice Accountant") }
  let(:assistant)  { create(:user, role: :auditor, email: "anna@firm.test", full_name: "Anna Assistant") }
  let(:reader)     { create(:user, role: :manager, email: "rita@firm.test", full_name: "Rita Reader") }
  let!(:owner_membership)      { create(:user_entity, :admin, user: owner, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let!(:reader_membership)     { create(:user_entity, :manager, user: reader, entity: entity) }
  let(:purchases) { create(:journal, :purchase) }
  let(:sales)     { create(:journal, :sale) }

  def entry_in(journal)
    entry = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, status: :draft)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: 100, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: account_440, debit: 0, credit: 100)
    Accounting::PostJournalEntry.call!(entry: entry)
    entry.reload
  end

  let!(:entry) { entry_in(purchases) }

  def task_on(target, user: accountant, **attrs) = Accounting::CreateTask.call(user: user, title: "Missing invoice", target: target, **attrs)

  describe "creating a task" do
    it "is linked to the ledger line it was made from, and counts for its entry (criterion 1)" do
      line = entry.lines.first
      result = task_on(line)

      expect(result).to be_success
      expect(result[:task]).to have_attributes(target: line, author_id: accountant.id, status: "open")
      expect(Accounting::Task.about(line)).to eq([ result[:task] ])
      expect(Accounting::TaskTargets.entry_of(line)).to eq(entry)
    end

    it "can be about an entry, an account, a partner, a bank line, a period or a document" do
      targets = [ entry, account_604, create(:partner), create(:bank_transaction), create(:period_lock), create(:document) ]

      expect(targets.map { |t| task_on(t).success? }).to all(be(true))
    end

    it "needs the right to manage tasks" do
      expect(task_on(entry, user: reader)).to be_failure
      expect(task_on(entry, user: assistant)).to be_success
    end

    it "refuses a target the author cannot see, and a thing of another entity" do
      accountant_membership.update!(journal_ids: [ sales.id ])
      expect(task_on(entry)).to be_failure

      other = ActsAsTenant.with_tenant(create(:entity)) { create(:partner) }
      expect(task_on(other)).to be_failure
    end

    it "tells the assignee, not its own author" do
      expect { task_on(entry, assignee: assistant) }.to change { Accounting::Notification.where(user: assistant, event: "task_assigned").count }.by(1)
      expect { task_on(entry, assignee: accountant) }.not_to change(Accounting::Notification, :count)
    end

    it "refuses an assignee who has no access to the entity" do
      stranger = create(:user)

      expect(task_on(entry, assignee: stranger)).to be_failure
    end

    it "changes nothing in a validated entry" do
      before = [ entry.updated_at, entry.lines.pluck(:id, :debit, :credit), entry.status ]

      task_on(entry)
      Accounting::AddComment.call(commentable: entry, user: accountant, body: "Looks fine")

      entry.reload
      expect([ entry.updated_at, entry.lines.pluck(:id, :debit, :credit), entry.status ]).to eq(before)
    end

    it "is about an anomaly of the consistency checks by its fingerprint, and closing it acknowledges nothing (criterion 6)" do
      task = task_on(entry, anomaly_fingerprint: "c04:440000:2026")[:task]

      Accounting::UpdateTask.call(task: task, user: accountant, status: "done")

      expect(task.reload).to be_done
      expect(Accounting::ConsistencyAcknowledgement.where(fingerprint: "c04:440000:2026")).to be_empty
    end
  end

  describe "changing a task" do
    let(:task) { task_on(entry)[:task] }

    it "records who closed it and when, and clears it when it is reopened" do
      Accounting::UpdateTask.call(task: task, user: assistant, status: "done")
      expect(task.reload).to have_attributes(status: "done", completed_by_id: assistant.id)
      expect(task.completed_at).to be_present

      Accounting::UpdateTask.call(task: task, user: assistant, status: "open")
      expect(task.reload).to have_attributes(completed_at: nil, completed_by_id: nil)
    end

    it "tells a new assignee once" do
      expect { Accounting::UpdateTask.call(task: task, user: accountant, assignee: assistant) }.to change { Accounting::Notification.where(user: assistant).count }.by(1)
      expect { Accounting::UpdateTask.call(task: task, user: accountant, assignee: assistant, priority: "high") }.not_to change(Accounting::Notification, :count)
    end

    it "does not move a task to another target" do
      Accounting::UpdateTask.call(task: task, user: accountant, target: account_604)

      expect(task.reload.target).to eq(entry)
    end

    it "is for those who manage tasks" do
      expect(Accounting::UpdateTask.call(task: task, user: reader, status: "done")).to be_failure
    end

    it "keeps the history in the audit trail" do
      Accounting::UpdateTask.call(task: task, user: accountant, status: "blocked")

      expect(Accounting::AuditLog.where(auditable_type: "Accounting::Task", auditable_id: task.id).count).to be >= 2
    end
  end

  describe "visibility (criterion 3)" do
    let!(:other_entry) { entry_in(sales) }
    let!(:mine)   { task_on(entry)[:task] }
    let!(:theirs) { task_on(other_entry)[:task] }

    it "follows the target: an access limited to the purchases journal does not see the task of a sales entry" do
      assistant_membership.update!(journal_ids: [ purchases.id ])

      expect(Accounting::Task.visible_to(assistant)).to contain_exactly(mine)
      expect(Accounting::Task.visible_to(accountant)).to contain_exactly(mine, theirs)
    end

    it "follows the target for a ledger line too" do
      line_task = task_on(other_entry.lines.first)[:task]
      assistant_membership.update!(journal_ids: [ purchases.id ])

      expect(Accounting::Task.visible_to(assistant)).not_to include(line_task)
    end

    it "does not let comment on what one cannot see, and the comments follow their task" do
      assistant_membership.update!(journal_ids: [ purchases.id ])

      expect(Accounting::AddComment.call(commentable: theirs, user: assistant, body: "hello")).to be_failure
      expect(Accounting::AddComment.call(commentable: other_entry, user: assistant, body: "hello")).to be_failure
      expect(Accounting::AddComment.call(commentable: mine, user: assistant, body: "hello")).to be_success
    end

    it "shows a task about nothing only to its author, its assignee and those who manage tasks" do
      loose = Accounting::CreateTask.call(user: assistant, title: "General note", assignee: accountant)[:task]

      expect(Accounting::Task.visible_to(assistant)).to include(loose)
      expect(Accounting::Task.visible_to(accountant)).to include(loose)
      expect(Accounting::Task.visible_to(reader)).not_to include(loose)
    end

    it "does not show the tasks of another entity" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:user_entity, :accountant, user: accountant, entity: ActsAsTenant.current_tenant); Accounting::Task.create!(title: "Foreign") }

      expect(Accounting::Task.visible_to(accountant)).not_to include(foreign)
    end
  end

  describe "comments and mentions (criterion 2)" do
    let(:task) { task_on(entry)[:task] }

    it "tells the person named, once, however many times they are named or the comment is saved" do
      result = Accounting::AddComment.call(commentable: task, user: accountant, body: "@anna please look, @anna it is urgent")

      expect(result[:comment].mentioned_user_ids).to eq([ assistant.id ])
      expect(Accounting::Notification.where(user: assistant, event: "mention").count).to eq(1)

      Accounting::EditComment.call(comment: result[:comment], user: accountant, body: "@anna please look again")
      expect(Accounting::Notification.where(user: assistant, event: "mention").count).to eq(1)
    end

    it "tells a person added by an edit, once" do
      comment = Accounting::AddComment.call(commentable: task, user: accountant, body: "@anna look")[:comment]

      Accounting::EditComment.call(comment: comment, user: accountant, body: "@anna and @olivia look")

      expect(Accounting::Notification.where(event: "mention").pluck(:user_id)).to match_array([ assistant.id, owner.id ])
    end

    it "tells nobody for a name that is unknown, for the author, or for someone who sees nothing of it" do
      reader_membership.update!(journal_ids: [ sales.id ])

      result = Accounting::AddComment.call(commentable: task, user: accountant, body: "@nobody @alice @rita")

      expect(result[:ignored_mentions]).to match_array(%w[nobody alice rita])
      expect(Accounting::Notification.where(event: "mention")).to be_empty
    end

    it "does not take an e-mail address for a mention" do
      result = Accounting::AddComment.call(commentable: task, user: accountant, body: "write to anna@firm.test")

      expect(result[:comment].mentioned_user_ids).to eq([])
    end

    it "is not a mention when two members share the name before the @" do
      other = create(:user, email: "anna@other.test")
      create(:user_entity, :assistant, user: other, entity: entity)

      result = Accounting::AddComment.call(commentable: task, user: accountant, body: "@anna")

      expect(result[:ignored_mentions]).to eq([ "anna" ])
    end

    it "needs the right to comment, and a text" do
      expect(Accounting::AddComment.call(commentable: task, user: reader, body: "hi")).to be_failure
      expect(Accounting::AddComment.call(commentable: task, user: accountant, body: "  ")).to be_failure
    end

    it "makes a thread: a reply belongs to the thread of the comment it answers" do
      first = Accounting::AddComment.call(commentable: task, user: accountant, body: "Where is it?")[:comment]
      reply = Accounting::AddComment.call(commentable: task, user: assistant, body: "In the mail", parent: first)

      expect(reply[:comment].parent).to eq(first)
      expect(first.replies).to eq([ reply[:comment] ])
      other_thread = Accounting::AddComment.call(commentable: entry, user: accountant, body: "Elsewhere")[:comment]
      expect(Accounting::AddComment.call(commentable: task, user: assistant, body: "No", parent: other_thread)).to be_failure
    end

    it "is about an entry directly too, and settled or opened again" do
      comment = Accounting::AddComment.call(commentable: entry, user: accountant, body: "Check the VAT")[:comment]

      Accounting::ResolveComment.call(comment: comment, user: assistant)
      expect(comment.reload).to have_attributes(resolved_by_id: assistant.id)
      expect(comment.resolved_at).to be_present

      Accounting::ResolveComment.call(comment: comment, user: assistant, resolved: false)
      expect(comment.reload.resolved_at).to be_nil
    end
  end

  describe "editing and hiding (criterion 4)" do
    let(:task) { task_on(entry)[:task] }
    let!(:comment) { Accounting::AddComment.call(commentable: task, user: accountant, body: "First version")[:comment] }

    it "lets the author edit for fifteen minutes, and no longer" do
      expect(Accounting::EditComment.call(comment: comment, user: accountant, body: "Second version")).to be_success
      expect(comment.reload).to have_attributes(body: "Second version")
      expect(comment.edited_at).to be_present

      travel_to(16.minutes.from_now) do
        expect(Accounting::EditComment.call(comment: comment, user: accountant, body: "Third version")).to be_failure
      end
      expect(comment.reload.body).to eq("Second version")
    end

    it "does not let anyone else edit it" do
      expect(Accounting::EditComment.call(comment: comment, user: owner, body: "Mine now")).to be_failure
    end

    it "is never deleted" do
      expect { comment.destroy }.to raise_error(Accounting::ImmutableRecordError)
      expect(Accounting::Comment.exists?(comment.id)).to be(true)
    end

    it "is hidden by its author or by whoever manages tasks, kept, and audited" do
      Accounting::HideComment.call(comment: comment, user: owner)

      expect(comment.reload).to be_hidden
      expect(comment.body).to eq("First version")
      expect(Accounting::Comment.shown).not_to include(comment)
      log = Accounting::AuditLog.where(auditable_type: "Accounting::Comment", auditable_id: comment.id, action: "comment_hidden").sole
      expect(log.user_id).to eq(owner.id)
    end

    it "is not hidden by a reader, and not edited once hidden" do
      expect(Accounting::HideComment.call(comment: comment, user: reader)).to be_failure

      Accounting::HideComment.call(comment: comment, user: accountant)
      expect(Accounting::EditComment.call(comment: comment, user: accountant, body: "Again")).to be_failure
    end
  end
end
