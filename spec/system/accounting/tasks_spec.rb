require "rails_helper"

# F08: the journey of a person: from an entry, make a task for a colleague, comment and name someone, see it in « My tasks », close it.
RSpec.describe "Tasks and comments", type: :system, js: true do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant, email: "alice@firm.test", full_name: "Alice Accountant") }
  let(:assistant)  { create(:user, role: :auditor, email: "anna@firm.test", full_name: "Anna Assistant") }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let(:journal) { create(:journal, :purchase) }

  before do
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      @entry = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 5, status: :draft, reference: nil)
      create(:journal_entry_line, journal_entry: @entry, account: account_604, debit: 80, credit: 0)
      create(:journal_entry_line, journal_entry: @entry, account: account_440, debit: 0, credit: 80)
      Accounting::PostJournalEntry.call!(entry: @entry)
    end
    login_as accountant, scope: :user
  end

  it "makes a task from an entry for a colleague, comments with a mention, and closes it" do
    visit accounting_journal_entry_path(@entry.reload)
    click_link "Add a task"

    expect(page).to have_content("About:")
    fill_in "Title", with: "Invoice missing"
    select "Anna Assistant", from: "Assigned to"
    select "Missing document", from: "Type"
    click_button "Save"

    expect(page).to have_content("Task created")
    expect(page).to have_content("Invoice missing")

    fill_in "body", with: "@anna can you ask the supplier?"
    click_button "Refuse" if page.has_button?("Refuse", wait: 1) # the cookie banner is fixed at the bottom of the window
    click_button "Comment"

    expect(page).to have_content("can you ask the supplier?")
    expect(Accounting::Notification.where(user: assistant, event: "mention").count).to eq(1)

    visit accounting_journal_entry_path(@entry)
    expect(page).to have_content("1 task")

    visit accounting_tasks_path(scope: "all")
    click_link "Invoice missing"
    click_link "Edit"
    select "Done", from: "Status"
    click_button "Save"

    expect(page).to have_content("Task updated")
    expect(page).to have_content("Closed")
    expect(Accounting::Task.last).to be_done
  end

  it "shows the person what they were told, and takes them to the task" do
    task = Accounting::CreateTask.call(user: accountant, title: "For Anna", assignee: assistant, target: @entry)[:task]
    login_as assistant, scope: :user

    visit accounting_notifications_path
    expect(page).to have_content("Task assigned to you")
    click_button "Read and open"

    expect(page).to have_current_path(accounting_task_path(task))
    expect(page).to have_content("For Anna")
  end
end
