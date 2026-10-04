require "rails_helper"

# F07 §10: the "Reverse" button of a validated entry: preview, reason, the counter-entry.
RSpec.describe "Reversing an entry", type: :system, js: true do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:journal) { create(:journal, :cash) }

  before do
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      @entry = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 30, status: :draft, description: "Office rent")
      create(:journal_entry_line, journal_entry: @entry, account: account_604, debit: 800, credit: 0)
      create(:journal_entry_line, journal_entry: @entry, account: account_440, debit: 0, credit: 800)
      Accounting::PostJournalEntry.call!(entry: @entry)
    end
    login_as accountant, scope: :user
  end

  it "previews the counter-entry, asks for the reason and posts it" do
    visit accounting_journal_entry_path(@entry)
    click_link "Reverse…"

    expect(page).to have_content("The counter-entry")
    fill_in "reason", with: "Booked on the wrong account"
    click_button "Reverse the entry"

    expect(page).to have_content("Entry reversed by")
    expect(@entry.reload).to be_reversed
    expect(@entry.reversal).to be_posted
  end

  it "does not reverse without a reason" do
    visit reversal_accounting_journal_entry_path(@entry)
    click_button "Reverse the entry"

    expect(@entry.reload).to be_posted
  end
end
