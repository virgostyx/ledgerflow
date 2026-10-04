require "rails_helper"

# F07 §10, screen: the reversal preview (inverse lines, date, warnings, confirmation of the unlettering), the date and the confirmation
# sent to the service, the planned reversal date on the entry form.
RSpec.describe "Entry reversal screen (F07)", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let(:auditor)    { create(:user, role: :auditor) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:auditor_membership) { create(:user_entity, :assistant, user: auditor, entity: entity) }
  let(:journal)  { create(:journal, :cash) }
  let(:supplier) { create(:partner, :supplier) }
  let(:today)    { fiscal_year.start_date + 100 }

  def post_entry(partner: nil)
    entry = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: today, status: :draft, description: "Rent")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: account_604, debit: 121, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: account_440, partner: partner, debit: 0, credit: 121)
    Accounting::PostJournalEntry.call!(entry: entry)
    entry.reload
  end

  before { sign_in accountant }

  describe "GET reversal" do
    it "shows the inverse lines, the date, and a field for the reason" do
      entry = post_entry
      get reversal_accounting_journal_entry_path(entry)

      expect(response.body).to include("Reason").and include("604000").and include(today.iso8601)
      expect(response.body).not_to include("confirm_unletter")
    end

    it "warns when the period is locked, with the date the reversal will have" do
      entry = post_entry
      create(:period_lock, starts_on: today - 5, ends_on: today + 5)
      get reversal_accounting_journal_entry_path(entry)

      expect(response.body).to include("locked").and include((today + 6).strftime("%d/%m/%Y"))
    end

    it "asks to confirm the unlettering when lines are lettered" do
      entry = post_entry(partner: supplier)
      payable = entry.lines.find_by(account: account_440)
      other = create(:journal_entry, journal: journal, fiscal_year: fiscal_year, entry_date: today + 1, status: :draft)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      pay = create(:journal_entry_line, journal_entry: other, account: account_440, partner: supplier, debit: 121, credit: 0)
      create(:journal_entry_line, journal_entry: other, account: account_570, debit: 0, credit: 121)
      Accounting::PostJournalEntry.call!(entry: other)
      Accounting::LetterLines.call(lines: [ payable, pay ], user: accountant)

      get reversal_accounting_journal_entry_path(entry)

      expect(response.body).to include("confirm_unletter")
    end

    it "is refused to a role that cannot reverse" do
      sign_in auditor
      get reversal_accounting_journal_entry_path(post_entry)

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "POST reverse" do
    it "takes the date chosen" do
      entry = post_entry
      post reverse_accounting_journal_entry_path(entry), params: { reason: "typo", date: (today + 3).to_s }

      expect(entry.reload.reversal.entry_date).to eq(today + 3)
    end

    it "says where it moved the date" do
      entry = post_entry
      create(:period_lock, starts_on: today - 5, ends_on: today + 5)
      post reverse_accounting_journal_entry_path(entry), params: { reason: "typo" }

      expect(flash[:notice]).to include("locked")
    end

    it "refuses a lettered entry unless the unlettering is confirmed" do
      entry = post_entry(partner: supplier)
      payable = entry.lines.find_by(account: account_440)
      payable.update_columns(lettering_id: create(:lettering, account: account_440).id)

      post reverse_accounting_journal_entry_path(entry), params: { reason: "typo" }
      expect(flash[:alert]).to include("confirm")
      expect(entry.reload).to be_posted

      post reverse_accounting_journal_entry_path(entry), params: { reason: "typo", confirm_unletter: "1" }
      expect(entry.reload).to be_reversed
    end
  end

  describe "the planned reversal date of an entry" do
    it "is kept when the entry is created, and shown" do
      post accounting_journal_entries_path, params: { accounting_journal_entry: {
        journal_id: journal.id, fiscal_year_id: fiscal_year.id, entry_date: today.to_s, description: "Prepaid", auto_reverse_on: (today + 60).to_s,
        lines_attributes: { "0" => { account_id: account_604.id, debit: "50", credit: "0" }, "1" => { account_id: account_440.id, debit: "0", credit: "50" } }
      } }

      entry = Accounting::JournalEntry.order(:id).last
      expect(entry.auto_reverse_on).to eq(today + 60)
      get accounting_journal_entry_path(entry)
      expect(response.body).to include((today + 60).strftime("%d/%m/%Y"))
    end
  end
end
