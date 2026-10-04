require "rails_helper"

# F10: the journey of a person in the assistant: start the closing, prepare the next year, confirm a manual step, skip one that does not block, and see the progress move.
RSpec.describe "Closing assistant", type: :system, js: true do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before do
    entity.update!(vat_regime: :franchise)
    login_as accountant, scope: :user
    visit accounting_closing_runs_path
    click_button "Refuse" if page.has_button?("Refuse", wait: 1) # the cookie banner is fixed at the bottom of the window
  end

  it "starts the closing, creates the next year, confirms and skips steps, and shows each step as it stands" do
    click_button "Start the closing"

    expect(page).to have_content("Closing of #{fiscal_year.year}")
    expect(page).to have_content("1. Preparation")
    expect(page).to have_content("18. Approval")
    expect(page).to have_content("The next fiscal year does not exist yet.")

    within("#step-preparation") { click_button "Do it" }
    click_button "Confirm" # the application's own confirmation modal
    expect(page).to have_css("#step-preparation", text: "The next fiscal year exists.")
    expect(Accounting::FiscalYear.find_by(start_date: fiscal_year.end_date + 1)).to be_present

    within("#step-stock") do
      fill_in "Comment", with: "No stock held"
      click_button "Confirm"
    end
    expect(page).to have_css("#step-stock", text: "Done")

    within("#step-provisions") do
      fill_in "Reason to skip", with: "Nothing to provide"
      click_button "Skip"
    end
    expect(page).to have_css("#step-provisions", text: "Skipped")

    expect(page).to have_content("Progress")
    expect(Accounting::ClosingRun.last.progress).to be > 0
  end

  it "says what blocks a step, with the screen that explains it" do
    create(:journal_entry, :draft, journal: create(:journal, :purchase), fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 2)
    click_button "Start the closing"

    within("#step-entries_complete") do
      expect(page).to have_content("1 entry in draft")
      expect(page).to have_link("Drafts")
    end
  end
end
