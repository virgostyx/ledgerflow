require "rails_helper"

# F09: the journey of a person: prepare the reminders, open a customer, change the text, put one line in dispute, validate, see it sent.
RSpec.describe "Customer reminders", type: :system, js: true do
  include ActiveJob::TestHelper
  include_context "with open customer lines"

  let(:accountant) { create(:user, role: :accountant, email: "alice@firm.test", full_name: "Alice Accountant") }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before do
    ActionMailer::Base.deliveries.clear
    open_line(amount: 100, days_overdue: 30)
    @disputed = open_line(amount: 40, days_overdue: 25)
    login_as accountant, scope: :user
  end

  it "prepares, reads, edits, disputes a line, validates, and sends only then" do
    visit accounting_dunning_runs_path
    click_button "Refuse" if page.has_button?("Refuse", wait: 1) # the cookie banner is fixed at the bottom of the window
    click_button "Prepare reminders"

    expect(page).to have_content("Nothing has been sent")
    expect(page).to have_content("Alice")
    expect(page).to have_content("Level 1")
    expect(ActionMailer::Base.deliveries).to be_empty

    click_link "Alice"
    expect(page).to have_content("Statement of account")
    fill_in "Subject", with: "A friendly reminder"
    click_button "Save"
    expect(page).to have_content("Reminder updated")

    within(:xpath, "//tbody/tr[td[normalize-space()='40,00 €']]") { click_button "Dispute" }
    expect(page).to have_content("Line updated")
    expect(@disputed.reload).to be_disputed

    click_link "Reminders", match: :first
    expect(ActionMailer::Base.deliveries).to be_empty
    visit accounting_dunning_run_path(Accounting::DunningRun.last)
    click_button "Send the validated reminders"
    click_button "Confirm" # the app's own confirmation modal

    expect(page).to have_content("being sent")
    perform_enqueued_jobs
    visit accounting_dunning_run_path(Accounting::DunningRun.last)
    expect(page).to have_content("Sent")
    expect(ActionMailer::Base.deliveries.sole.subject).to eq("A friendly reminder")
  end
end
