require "rails_helper"

# F01: an assistant enters drafts and reconciles; nothing it does validates an entry (spec §4 capability table).
RSpec.describe "The assistant role", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:assistant) { create(:user, role: :auditor) } # the global role no longer matters
  let!(:membership) { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let!(:journal) { create(:journal, :purchase) }

  before { sign_in assistant }

  let(:entry_params) do
    { accounting_journal_entry: { journal_id: journal.id, fiscal_year_id: fiscal_year.id, entry_date: Date.current, description: "By an assistant",
                                  lines_attributes: { "0" => { account_id: account_604.id, debit: "100.00", credit: "0", label: "Charges" },
                                                      "1" => { account_id: account_440.id, debit: "0", credit: "100.00", label: "Fournisseur" } } } }
  end

  it "enters a draft entry, which stays a draft" do
    expect { post accounting_journal_entries_path, params: entry_params }.to change(Accounting::JournalEntry, :count).by(1)

    entry = Accounting::JournalEntry.last
    expect(entry).to be_draft
    expect(entry.created_by).to eq(assistant)
    expect(response).to redirect_to(accounting_journal_entry_path(entry))
  end

  it "cannot post a draft" do
    entry = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year)

    post post_entry_accounting_journal_entry_path(entry)

    expect(entry.reload).to be_draft
  end

  it "cannot reverse a validated entry" do
    entry = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year)
    Accounting::PostJournalEntry.call(entry: entry)

    post reverse_accounting_journal_entry_path(entry), params: { reason: "nope" }

    expect(entry.reload).to be_posted
  end

  it "cannot validate an invoice" do
    invoice = create(:invoice, :draft, fiscal_year: fiscal_year)

    post validate_invoice_accounting_invoice_path(invoice)

    expect(invoice.reload).to be_draft
  end

  it "cannot post depreciation entries" do
    expect { post post_depreciation_accounting_fixed_assets_path, params: { fiscal_year_id: fiscal_year.id } }
      .not_to change(Accounting::JournalEntry, :count)
  end

  it "reads the reports on screen" do
    get accounting_reports_trial_balance_path

    expect(response).to have_http_status(:ok)
  end

  it "downloads a report, the assistant being one of the roles that export" do
    get accounting_reports_trial_balance_path(format: :csv)

    expect(response).to have_http_status(:ok)
  end

  it "does not open the screens of the owners (users, periods unlock, settings)" do
    get accounting_settings_memberships_path
    expect(response).to redirect_to(accounting_root_path)

    lock = create(:period_lock)
    post unlock_accounting_period_lock_path(lock), params: { reason: "x" }
    expect(lock.reload).to be_locked
  end
end
