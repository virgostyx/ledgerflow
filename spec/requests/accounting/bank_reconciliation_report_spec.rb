require "rails_helper"

RSpec.describe "Accounting::Reports bank_reconciliation_report", type: :request, bullet_strict: true do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:bank_account) { create(:bank_account, entity: entity) }
  let(:gl_account)   { bank_account.journal.default_account }
  let(:other_account) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit) }
  let(:journal) { create(:journal, :purchase) }

  before { sign_in accountant }

  def post_entry(amount:)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: gl_account, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: other_account, debit: 0, credit: amount)
    entry.post!
    entry
  end

  it "returns 200 and shows B/A/expected/gap" do
    entry = post_entry(amount: 100)
    create(:bank_transaction, bank_account: bank_account, amount: 100, journal_entry: entry, status: :reconciled)

    get accounting_reports_bank_reconciliation_report_path(bank_account_id: bank_account.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Statement balance", "Accounting balance")
  end

  it "returns 200 with an invalid as_of date" do
    get accounting_reports_bank_reconciliation_report_path(bank_account_id: bank_account.id, as_of: "invalid")
    expect(response).to have_http_status(:ok)
  end

  it "freezes a zero-gap reconciliation, immutably" do
    entry = post_entry(amount: 100)
    create(:bank_transaction, bank_account: bank_account, amount: 100, journal_entry: entry, status: :reconciled)

    expect {
      post accounting_reports_freeze_bank_reconciliation_report_path,
           params: { bank_account_id: bank_account.id, as_of: Date.current }
    }.to change(Accounting::BankReconciliationReport, :count).by(1)

    expect(response).to redirect_to(accounting_reports_bank_reconciliation_report_path(bank_account_id: bank_account.id, as_of: Date.current))
    report = Accounting::BankReconciliationReport.last
    expect(report.content_hash).to be_present
  end
end
