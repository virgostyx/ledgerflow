require "rails_helper"

# B03a "spec système du sélecteur et du bandeau": a person asks for the books as they were known a few seconds ago, sees the banner and the older figures, follows a link down
# to the ledger without losing the instant, finds nothing to change on the screen, and comes back to today.
RSpec.describe "The historical view, from the selector to the way back", type: :system do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:journal) { create(:journal, :purchase) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_entry(amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: "S-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    entry.reload
  end

  it "shows the figures of an earlier instant, keeps it on the way down to the ledger, and comes back to today" do
    first = post_entry(BigDecimal("111.00"))
    sleep 1.2
    next_posting_instant # one spec is one transaction, which has one instant of validation
    post_entry(BigDecimal("222.00"))
    cutoff = first.posted_at + 1 # the selector gives seconds, so it falls between the two validations, 1.2 seconds apart

    login_as accountant, scope: :user
    visit accounting_reports_trial_balance_path(fiscal_year_id: fiscal_year.id)
    expect(page).to have_content("333,00")
    expect(page).to have_no_content("Historical view —")

    fill_in "known_at", with: cutoff.utc.strftime("%Y-%m-%dT%H:%M:%S")
    click_button "Show"

    expect(page).to have_content("Historical view —").and have_content("Read only")
    expect(page).to have_content("111,00")
    expect(page).to have_no_content("333,00")
    expect(page).to have_no_button("Validate")

    click_link "604000"
    expect(page).to have_current_path(/known_at=/)
    expect(page).to have_content("Historical view —")

    click_link "Back to today"
    expect(page).to have_no_content("Historical view —")
  end
end
