require "rails_helper"

# B03b "spec système du parcours « depuis mon dernier passage »": a person opens the page, comes back later and sees only what changed since, reads the detail, marks a
# change as reviewed, and erases their last visit.
RSpec.describe "What changed, since my last visit", type: :system do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:journal) { create(:journal, :purchase) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before do
    Accounting::HistoryStart.create!(starts_at: 1.day.ago)
    entity.update!(features: entity.features.merge("b03a" => true, "b03b" => true))
  end

  def post_entry(amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: [ Date.current, fiscal_year.end_date ].min, reference: "J-#{SecureRandom.hex(3)}", created_by_id: accountant.id)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    entry.reload
  end

  it "shows what changed since the last visit, lets a reviewer mark it, and forgets the visit on request" do
    before_visit = post_entry(BigDecimal("111.00"))
    sleep 0.3
    next_posting_instant

    login_as accountant, scope: :user
    visit accounting_changes_path(fiscal_year_id: fiscal_year.id)
    expect(page).to have_content("What changed")
    expect(page).to have_content("Entries added")

    sleep 1.2
    next_posting_instant
    after_visit = post_entry(BigDecimal("222.00"))

    visit accounting_changes_path(fiscal_year_id: fiscal_year.id)
    expect(page).to have_content("Entries added 1")
    expect(page).to have_content("Total of the movements €222.00") # what was validated before the last visit is not a change, it is the value at T1
    expect(page).to have_content("Sum of variations = sum of movements, gap 0.00")

    click_link "Detail"
    expect(page).to have_content(after_visit.reference)
    expect(page).to have_no_content(before_visit.reference)

    fill_in "comment", with: "checked against the invoice"
    click_button "Mark as reviewed"
    expect(page).to have_content("The change is marked as reviewed.")
    expect(page).to have_content("Reviewed by #{accountant.email}")

    click_button "Erase my last visit"
    expect(page).to have_content("Your last visit was erased.")
    expect(Accounting::UserVisit.where(user: accountant)).to be_empty
  end
end
